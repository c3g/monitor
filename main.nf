#!/usr/bin/env nextflow
nextflow.enable.dsl=2

@Grab('com.xlson.groovycsv:groovycsv:1.3')
@Grab('org.codehaus.groovy:groovy-all:2.2.2')
@Grab(group='org.xerial', module='sqlite-jdbc', version='3.36.0.3')

import static com.xlson.groovycsv.CsvParser.parseCsv

import groovy.sql.Sql
import groovy.text.markup.*
import groovy.text.*

params.ingest = false

include { T7   as Mgi_T7   } from './workflows/mgi'
include { G400 as Mgi_G400 } from './workflows/mgi'
include { Monitors as Mgi_Monitor } from './workflows/mgi'
include { RunSpecific } from './workflows/mgi'

workflow {

    def db = new MetadataDB(params.db, log)
    db.setup()

    if (params.ingest) {
        Channel.fromPath(params.oldeventpath).branch {
            unreadable: !it.canRead()
            empty: new Eventfile(it).isEmpty()
            ok: it.canRead()
                return new Eventfile(it)
        }.set{ eventfiles }

        eventfiles.unreadable.map { log.warn("Cannot read event file: ${it}") }
        eventfiles.empty.map      { log.warn("Empty event file: ${it}") }
        eventfiles.ok.map         { Eventfile evt -> db.insert(evt) }
    }

    Channel.watchPath(params.neweventpath).branch {
        unreadable: !it.canRead()
        readable: true
            return new Eventfile(it)
    }.set{ newEventfilesRaw }

    newEventfilesRaw.unreadable.map { log.warn ("Cannot read event file ${it}") }
    newEventfilesRaw.readable
    .branch {
        empty: it.isEmpty()
        mgit7: it.isMgiT7()
    }.set{ newEventfiles }

    newEventfiles.empty.map { log.warn ("Empty event file: ${it}") }

    Mgi_Monitor()
    newEventfiles.mgit7 | Mgi_T7
}

workflow BasicMonitor {
    Mgi_Monitor()
}

workflow RunOne {
    RunSpecific()
}


process EmailAlertFinishTest {
    publishDir "outputs/email", mode: 'copy'
    executor 'local'

    input:
    val multiqc_json

    output:
    file('*.html')

    exec:
    def email_fields = [run: multiqc_json, workflow: workflow]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    def templateFile = new File("$projectDir/assets/email_MGI_run_finish.tpl")
    Writable output = engine.createTemplate(templateFile).make(email_fields)
    def finalHtml = new File("${task.workDir}/dummy_email.html")
    finalHtml.text = output.toString()
}


workflow EmailDebug {
    Channel.watchPath("assets/*.tpl", 'create,modify')
    | map { new MultiQC(file("assets/multiqc/multiqc_data.json"))} \
    | EmailAlertFinishTest
}

workflow.onComplete {

    if(params.emailoncrash) {
        def msg = """\
            Pipeline execution summary
            ---------------------------
            Completed at: ${workflow.complete}
            Duration    : ${workflow.duration}
            Success     : ${workflow.success}
            workDir     : ${workflow.workDir}
            exit status : ${workflow.exitStatus}
            """.stripIndent()

        sendMail {
            to 'robert.syme@mcgill.ca'
            from 'abacus.genome@mail.mcgill.ca'
            subject 'Alert: Monitor stopped'
            body: msg
        }
    }

}
