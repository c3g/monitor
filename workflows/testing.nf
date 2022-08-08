
process EmailAlertFinishTest {
    publishDir "outputs/testing/email", mode: 'copy'
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
    def finalHtml = new File("${task.workDir}/email_MGI_run_finish.html")
    finalHtml.text = output.toString()
}

workflow EmailDebug {
    Channel.watchPath("assets/*.tpl", 'create,modify')
    | map { new MultiQC(file("assets/multiqc/multiqc_data.json")) }
    | EmailAlertFinishTest
}


if (includeFile && matcher.matches(path) && attrs.isRegularFile() && (includeHidden || !isHidden(fullPath))) {
    def result = relative ? path : fullPath
    singleParam ? action.call(result) : action.call(result,attrs)
}
