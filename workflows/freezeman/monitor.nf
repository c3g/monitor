@Grab('org.codehaus.groovy:groovy-all:2.2.2')
@Grab(group='org.xerial', module='sqlite-jdbc', version='3.36.0.3')

import groovy.sql.Sql
import groovy.text.markup.TemplateConfiguration
import groovy.text.markup.MarkupTemplateEngine

process EmailAlertFinish {
    executor 'local'
    errorStrategy = {task.attempt <= 2 ? 'retry' : 'ignore'}

    input:
    tuple val(multiqc_html), val(multiqc_json)

    when:
    params.sendmail

    exec:
    def db = new MetadataDB(params.db, log)
    def runinf = db.latestRunInfofile(multiqc_json.flowcell)
    def platform = (runinf.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        run: multiqc_json,
        workflow: workflow,
        platform: platform,
        event: runinf
    ]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    File templateFile = new File("$projectDir/assets/email_run_finish.groovy")
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
    executor 'local'
    errorStrategy = {task.attempt <= 2 ? 'retry' : 'ignore'}
    maxForks 1
    module 'mugqic_dev/MultiQC_C3G/1.17_mcj'

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
    errorStrategy = {task.attempt <= 2 ? 'retry' : 'ignore'}
    maxForks 1

    input:
    tuple path(report_html), val(multiqc)

    script:
    def db = new MetadataDB(params.db, log)
    def runinf = db.latestRunInfofile(multiqc.flowcell)
    def key = params.sftpssharbutus
    """
    sftp -i $key -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    put $report_html /datahub297/MGI_validation/${runinf.year}/${multiqc.run}.report.html
    chmod 664 /datahub297/MGI_validation/${runinf.year}/${multiqc.run}.report.html
    EOF
    """
}

process FreezemanIngest {
    tag { reportfile.getBaseName() }
    executor 'local'
    errorStrategy = {task.attempt <= 2 ? 'retry' : 'ignore'}
    maxForks 1
    module 'mugqic/python/3.10.2'

    input:
    path(reportfile)

    """
    python freezemanIngestor.py \\
        -url http://f5kvm-biobank-qc.genome.mcgill.ca/api/ \\
        -user ehenrion \\
        -password <??password??> \\
        -filepath $reportfile

    """
}

process SummaryReportUpload {
    tag { report.name - "_L01.summaryReport.html" }
    executor 'local'
    errorStrategy = {task.attempt <= 2 ? 'retry' : 'ignore'}
    maxForks 1

    input:
    path(report)

    script:
    def db = new MetadataDB(params.db, log)
    def runinf = db.latestRunInfofile(multiqc.flowcell)
    def key = params.sftpssharbutus
    """
    sftp -i $key -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    put $report /datahub297/MGI_validation/${runinf.year}/${report.name}
    chmod 664 /datahub297/MGI_validation/${runinf.year}/${report.name}
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
    donefiles = Channel.watchPath("${params.mgi.outdir}/*/job_output/final_notification/final_notification.*.done", 'create,modify')

    // Upload to GenAP + Send end-of-processing email notification
    donefiles
    | map { donefile -> [donefile.getParent().getParent().getParent(), donefile] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)] }
    | (GenapUpload & EmailAlertFinish)

    // // Ingestion of the GenPipes report (JSON) into Freezeman (one report per lane)
    // donefiles
    // | map { donefile -> "${donefile.getParent().getParent().getParent()}/report/*.run_validation_report.json" }
    // | splitText()
    // | FreezemanIngest
}
