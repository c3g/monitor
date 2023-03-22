import groovy.text.markup.TemplateConfiguration
import groovy.text.markup.MarkupTemplateEngine

import static com.xlson.groovycsv.CsvParser.parseCsv

process OnStartHTML {
    publishDir "outputs/testing/email", mode: 'copy'
    executor 'local'

    input:
    tuple val(template), val(multiqc_json)

    output:
    file('*.html')

    exec:
    def db = new MetadataDB(params.db, log)
    def testEventFile = db.latestEventfile(multiqc_json.flowcell)
    def rows = parseCsv(testEventFile.text, separator: '\t').collect()
    def platform = (testEventFile.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        flowcell: multiqc_json.flowcell,
        eventfile_rows: rows,
        platform: platform,
        workflow: workflow
    ]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    File templateFile = new File(template.toString())
    Writable output = engine.createTemplate(templateFile).make(email_fields)
    File finalHtml = new File("${task.workDir}/email_run_start.html")
    finalHtml.text = output.toString()
}

process OnFinishHTML {
    publishDir "outputs/testing/email", mode: 'copy'
    executor 'local'

    input:
    tuple val(template), val(multiqc_json)

    output:
    file('*.html')

    exec:
    def db = new MetadataDB(params.db, log)
    def testEventFile = db.latestEventfile(multiqc_json.flowcell)
    def platform = (testEventFile.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        run: multiqc_json,
        workflow: workflow,
        platform: platform,
        event: testEventFile
    ]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    File templateFile = new File(template.toString())
    Writable output = engine.createTemplate(templateFile).make(email_fields)
    File finalHtml = new File("${task.workDir}/email_run_finish.html")
    finalHtml.text = output.toString()
}

workflow OnStartDebug {
    Channel.watchPath("$projectDir/assets/*start.groovy", 'create,modify')
    | map { [it, new MultiQC("$projectDir/assets/testing/multiqc_data.example.json")] }
    | OnStartHTML
}

workflow OnFinishDebug {
    Channel.watchPath("$projectDir/assets/*finish.groovy", 'create,modify')
    | map { [it, new MultiQC("$projectDir/assets/testing/multiqc_data.example.json")] }
    | OnFinishHTML
}

workflow FlagfileDebug {
    Channel.fromPath(params.mgi?.t7?.flags)
    | map { new MgiFlagfile(it) }
    | view { it }
}