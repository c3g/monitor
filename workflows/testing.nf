import groovy.text.markup.TemplateConfiguration
import groovy.text.markup.MarkupTemplateEngine

process OnFinishHTML {
    publishDir "outputs/testing/email", mode: 'copy'
    executor 'local'

    input:
    tuple val(template), val(multiqc_json)

    output:
    file('*.html')

    exec:
    def email_fields = [run: multiqc_json, workflow: workflow]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    def templateFile = new File(template.toString())
    Writable output = engine.createTemplate(templateFile).make(email_fields)
    def finalHtml = new File("${task.workDir}/email_MGI_run_finish.html")
    finalHtml.text = output.toString()
}

workflow OnFinishDebug {
    Channel.watchPath("$projectDir/assets/*.groovy", 'create,modify')
    | map { [it, new MultiQC("$projectDir/assets/testing/multiqc_data.example.json")] }
    | OnFinishHTML
}

workflow FlagfileDebug {
    Channel.fromPath(params.mgi?.t7?.flags)
    | map { new MgiFlagfile(it) }
    | view { it }
}