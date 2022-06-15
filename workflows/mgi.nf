@Grab('org.codehaus.groovy:groovy-all:2.2.2')
@Grab(group='org.xerial', module='sqlite-jdbc', version='3.36.0.3')
@Grab('com.xlson.groovycsv:groovycsv:1.3')

import static com.xlson.groovycsv.CsvParser.parseCsv

import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.Files

import groovy.sql.Sql
import groovy.text.markup.*
import groovy.text.*

params.skiprescan=false
params.nomail=false

process EmailAlertFinish {
    executor 'local'

    input:
    tuple val(multiqc_html), val(multiqc_json)

    when:
    !params.nomail

    exec:
    def email_fields = [run: multiqc_json, workflow: workflow]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    def templateFile = new File("$projectDir/assets/email_MGI_run_finish.tpl")
    Writable output = engine.createTemplate(templateFile).make(email_fields)

    log.debug("New run ${multiqc_json.flowcell} | Sending email to '${params.email.onfinish}'")

    sendMail {
        to params.email.onfinish
        from 'abacus.genome@mail.mcgill.ca'
        attach "$multiqc_html"
        subject "MGI run processing finished: flowcell ${multiqc_json.flowcell}"

        output.toString()
    }
}

process EmailAlertStart {
    executor 'local'

    input:
    val eventfile

    output:
    val eventfile

    when:
    !params.nomail

    exec:
    def rows = parseCsv(eventfile.text, separator: '\t').collect()

    def email_fields = [
        flowcell: eventfile.flowcell,
        eventfile_rows: rows,
    ]

    def engine = new groovy.text.GStringTemplateEngine()
    def html = new File("$projectDir/assets/email_T7_run_start.html")
    def html_template = engine.createTemplate(html).make(email_fields)

    Path tmpdir = Files.createTempDirectory("runprocessing");
    def tmpfile = new File(tmpdir.toFile(), eventfile.filename)
    tmpfile.write(eventfile.text)

    log.debug("New run ${eventfile.flowcell} | Sending email to '${params.email.onstart}'")

    sendMail {
        to params.email.onstart
        from 'abacus.genome@mail.mcgill.ca'
        attach "$tmpfile"
        subject "New T7 run - Processing started flowcell ${eventfile.flowcell}"

        html_template.toString()
    }

    tmpfile.delete()
    tmpdir.delete()
}

process GetGenpipes {
    input:
    val(commit)

    output:
    tuple val(commit), path("genpipes")

    script:
    if(params.genpipes)
        """
        ln -s ${params.genpipes} genpipes
        """
    else
        """
        git clone git@bitbucket.org:mugqic/genpipes.git
        cd genpipes
        git checkout $commit
        """
}

process BeginRunT7 {
    executor 'local'
    module 'mugqic/python/3.10.4'

    input:
    tuple val eventfile, path("genpipes")

    output:
    val eventfile

    script:
    def custom_ini = params.mgi.t7.custom_ini ? Paths.get(projectDir.toString(), params.mgi.t7.custom_ini) : ""
    """
export MUGQIC_INSTALL_HOME_PRIVATE=/lb/project/mugqic/analyste_private
module use \$MUGQIC_INSTALL_HOME_PRIVATE/modulefiles
export MUGQIC_PIPELINES_HOME=/home/rsyme/src/bitbucket.org/mugqic/genpipes

mkdir -p ${params.mgi.outdir}/${eventfile.flowcell}

cat <<EOF > ${eventfile.filename}
${eventfile.text}
EOF

\$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.py \\
    -c \$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.base.ini ${custom_ini} \\
    --genpipes_file genpipes_submitter.sh \\
    -o ${params.mgi.outdir}/${eventfile.flowcell} \\
    -j pbs \\
    -l debug \\
    -d /nb/Research/MGISeq/T7/R1100600200054/upload/workspace/${eventfile.flowcell} \\
    --flag /nb/Research/MGISeq/T7/R1100600200054/flag \\
    --run-id ${eventfile.flowcell} \\
    --no-json \\
    --splitbarcode-demux \\
    --type mgit7 \\
    -r ${eventfile.filename}
    """
}

process RunMultiQC {
    executor 'local'
    module 'mugqic_dev/MultiQC_C3G/1.12_beta'

    input:
    tuple val(rundir), path("config.yaml")

    output:
    tuple path("multiqc_report.html"), path("*/multiqc_data.json")

    """
    multiqc --runprocessing $rundir
    """
}

process GenapUpload {
    executor 'local'

    input:
    tuple path(report_html), val(multiqc)

    """
    sftp -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    put $report_html /datahub297/MGI_validation/2022/${multiqc.flowcell}.report.html
    chmod 664 /datahub297/MGI_validation/2022/${multiqc.flowcell}.report.html
    EOF
    """
}

workflow RunSpecific {
    Channel.fromPath(params.rundir)
    | map { [it, file(params.mgi.multiqc_config)] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)]} \
    | GenapUpload
}

workflow WatchForCheckpoints {
    log.info "Watching for checkpoint files at ${params.mgi.outdir}/*/job_output/checkpoint/*.done"
    // checkpoints = Channel.watchPath("${params.mgi.outdir}/*/job_output/checkpoint/*.done")

    // a = Channel.watchPath("${params.mgi.outdir}/220321_R2130400190016_10103_BV300096734_10103MG01B-dnbseqg400/job_output/checkpoint/*.done")
    // b = Channel.watchPath("${params.mgi.outdir}/220321_R2130400190016_10102_AV350007796_10102MG01A-dnbseqg400/job_output/checkpoint/*.done")
    a = Channel.watchPath("${params.mgi.outdir}/220323_R2130400190018_10104_AV300096788_10104MG02A-dnbseqg400/job_output/checkpoint/*.done")
    b = Channel.watchPath("${params.mgi.outdir}/220323_R2130400190018_10105_BV300096795_10105MG02B-dnbseqg400/job_output/checkpoint/*.done")

    a.mix(b)
    | map { [it.getParent().getParent().getParent(), file(params.mgi.multiqc_config)] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)]} \
    | GenapUpload
}

workflow WatchForFinish {
    // Channel.watchPath("${params.mgi.outdir}/*/job_output/final_notification/final_notification.*.done")

    a = Channel.watchPath("${params.mgi.outdir}/220321_R2130400190016_10103_BV300096734_10103MG01B-dnbseqg400/job_output/final_notification/final_notification.*.done")
    b = Channel.watchPath("${params.mgi.outdir}/220321_R2130400190016_10102_AV350007796_10102MG01A-dnbseqg400/job_output/final_notification/final_notification.*.done")

    a.mix(b)
    | map { [it.getParent().getParent().getParent(), file(params.mgi.multiqc_config)] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)]} \
    | EmailAlertFinish
}

workflow Monitors {
    WatchForCheckpoints()
    WatchForFinish()
}

workflow G400 {
    take:
    eventfiles

    main:
    def db = new MetadataDB(params.db, log)
}

workflow T7 {
    take:
    eventfiles

    main:
    def db = new MetadataDB(params.db, log)

    // Preexisting flag files go directly to the DB.
    Channel.fromPath(params.mgi.t7.flags)
    .map { new MgiFlagfile(it) }
    .map { db.insert(it) }

    // *New* flag files should be stored and then
    //   checked to see if we should begin processing
    log.info("Watching for new MGI T7 flag files at '${params.mgi.t7.flags}'")
    Channel.watchPath(params.mgi.t7.flags)
    .map { new MgiFlagfile(it) }
    .map { ff ->
        db.insert(ff)
        def evt = db.latestEventfile(ff.flowcell)
        if (evt == null) {
            log.debug("New flagfile (${ff.flowcell}) | No matching eventfile")
        } else if(evt.alreadyLaunched()) {
            log.debug("New flagfile (${ff.flowcell}) | Latest eventfile already launched: ${evt}")
        } else {
            log.debug("New flagfile (${ff.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromFlagfiles }

    eventfiles
    .map { Eventfile evt -> db.hasFlagfile(evt) ? evt : log.debug("New eventfile (${evt.flowcell}) | No matching flagfile") }
    .set { EventfilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    EventfilesForRunning
    | mix(EventfilesForRunningFromFlagfiles)
    | combine(GetGenpipes.out)
    | BeginRunT7
    | EmailAlertStart
    | map { Eventfile evt -> db.markAsLaunched(evt) }
}