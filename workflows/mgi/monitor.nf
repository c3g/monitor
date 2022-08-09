@Grab('org.codehaus.groovy:groovy-all:2.2.2')
@Grab(group='org.xerial', module='sqlite-jdbc', version='3.36.0.3')

import groovy.sql.Sql
import groovy.text.markup.TemplateConfiguration
import groovy.text.markup.MarkupTemplateEngine

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
    module 'mugqic_dev/MultiQC/runprocessing-dev'
    executor 'local'
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

    input:
    tuple path(report_html), val(multiqc)

    """
    sftp -P 22004 sftp_p25@sftp-arbutus.genap.ca <<EOF
    put $report_html /datahub297/MGI_validation/2022/${multiqc.flowcell}.report.html
    chmod 664 /datahub297/MGI_validation/2022/${multiqc.flowcell}.report.html
    EOF
    """
}

workflow WatchCheckpoints {
    log.info "Watching for checkpoint files at ${params.mgi.outdir}/*/job_output/checkpoint/*.stepDone"
    Channel.watchPath("${params.mgi.outdir}/*/job_output/checkpoint/*.stepDone")
    | map { donefile -> [donefile.getParent().getParent().getParent(), donefile] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)] }
    | GenapUpload
}

workflow WatchFinish {
    log.info "Watching for .done files at ${params.mgi.outdir}/*/job_output/final_notification/final_notification.*.done"
    Channel.watchPath("${params.mgi.outdir}/*/job_output/final_notification/final_notification.*.done")
    | map { donefile -> [donefile.getParent().getParent().getParent(), donefile] }
    | RunMultiQC
    | map { html, json -> [html, new MultiQC(json)] }
    | (EmailAlertFinish & GenapUpload)
}