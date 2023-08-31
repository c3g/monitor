@Grab('org.codehaus.groovy:groovy-all:2.2.2')
@Grab(group='org.xerial', module='sqlite-jdbc', version='3.36.0.3')

import groovy.sql.Sql
import groovy.text.markup.TemplateConfiguration
import groovy.text.markup.MarkupTemplateEngine

process EmailAlertFinish {
    executor 'local'
    errorStrategy 'terminate'

    input:
    tuple val(multiqc_html), val(multiqc_json)

    when:
    params.sendmail

    exec:
    def db = new MetadataDB(params.db, log)
    def evt = db.latestEventfile(multiqc_json.flowcell)
    def platform = (evt.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        run: multiqc_json,
        workflow: workflow,
        platform: platform,
        event: evt
    ]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    def templateFile = new File("$projectDir/assets/email_run_finish.groovy")
    Writable output = engine.createTemplate(templateFile).make(email_fields)

    sendMail {
        to params.email.onfinish
        from 'abacus.genome@mail.mcgill.ca'
        attach "$multiqc_html"
        subject "Run processing complete - ${multiqc_json.seqtype} - ${multiqc_json.flowcell}"

        output.toString()
    }
}

process RunMultiQC {
    tag { donefile.getBaseName() }
    module 'mugqic_dev/MultiQC_C3G/1.12_beta'
    executor 'local'
    errorStrategy 'terminate'
    maxForks 1

    input:
    tuple path(rundir), path(donefile)

    output:
    tuple path("multiqc_report.html"), path("*/multiqc_data.json")

    """
    multiqc $rundir \\
        --template c3g \\
        --runprocessing \\
        --interactive
    """
}

process GenapUpload {
    tag { multiqc.flowcell }
    executor 'local'
    maxForks 1
    errorStrategy 'retry'
    maxErrors 3

    input:
    tuple path(report_html), val(multiqc)

    script:
    def db = new MetadataDB(params.db, log)
    def evt = db.latestEventfile(multiqc.flowcell)
    """
    sftp -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    put $report_html /datahub297/MGI_validation/${evt.year}/${multiqc.run}.report.html
    chmod 664 /datahub297/MGI_validation/${evt.year}/${multiqc.run}.report.html
    EOF
    """
}

process SummaryReportUpload {
    tag { report.name - "_L01.summaryReport.html" }
    executor 'local'
    errorStrategy 'retry'
    maxErrors 3
    maxForks 1

    input:
    path(report)

    script:
    def db = new MetadataDB(params.db, log)
    def evt = db.latestEventfile(multiqc.flowcell)
    """
    sftp -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    put $report /datahub297/MGI_validation/${evt.year}/${report.name}
    chmod 664 /datahub297/MGI_validation/${evt.year}/${report.name}
    EOF
    """
}

workflow WatchCheckpoints {
    log.info "Watching for checkpoint files at ${params.mgi.outdir}/*/job_output/checkpoint/*.stepDone"
    donefiles = Channel.watchPath("${params.mgi.outdir}/*/job_output/checkpoint/*.stepDone", 'create,modify')

    // Run MultiQC on all donefiles
    donefiles
    | map { donefile -> [donefile.getParent().getParent().getParent(), donefile] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)] }
    | GenapUpload

    // If the donefile is the "basecall" donefile, then we can upload the MGI summaryReport.html
    donefiles
    | filter { donefile -> donefile.startsWith('basecall') }
    | map { donefile ->
        reportList = []
        rundir = donefile.getParent().getParent().getParent()
        rundir.eachFileRecurse(groovy.io.FileType.FILES) {
            if(it.name.endsWith('.summaryReport.html')) { reportList.append(it) }
        }
        reportList ?: null
    }
    | SummaryReportUpload
}

workflow WatchFinish {
    log.info "Watching for .done files at ${params.mgi.outdir}/*/job_output/final_notification/final_notification.*.done"
    Channel.watchPath("${params.mgi.outdir}/*/job_output/final_notification/final_notification.*.done", 'create,modify')
    | map { donefile -> [donefile.getParent().getParent().getParent(), donefile] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)] }
    | (GenapUpload & EmailAlertFinish)
}
