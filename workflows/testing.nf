import groovy.text.markup.TemplateConfiguration
import groovy.text.markup.MarkupTemplateEngine

import java.text.SimpleDateFormat

import static com.xlson.groovycsv.CsvParser.parseCsv

process OnStartClarityHTML {
    publishDir "outputs/testing/email", mode: 'copy'
    executor 'local'
    errorStrategy 'terminating'

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
        samples: rows,
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

process OnStartFreezemanHTML {
    publishDir "outputs/testing/email", mode: 'copy', overwrite: true
    executor 'local'
    errorStrategy 'terminating'

    input:
    tuple val(template), val(runinfo_json)

    output:
    file('*.html')

    exec:
    // println "YOYO"
    // println runinfo_json.instrument
    // println "YOYO"
    // def dformat = new SimpleDateFormat("yyMMdd")
    // println dformat.format(runinfo_json.startDate).toString()
    // println "YOYO"
    def db = new MetadataDB(params.db, log)
    def platform = (runinfo_json.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        flowcell: runinfo_json.flowcell,
        samples: runinfo_json.data.samples,
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

process OnFinishClarityHTML {
    publishDir "outputs/testing/email", mode: 'copy', overwrite: true
    executor 'local'
    errorStrategy 'terminating'

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

process OnFinishFreezemanHTML {
    publishDir "outputs/testing/email", mode: 'copy'
    executor 'local'
    errorStrategy 'terminating'

    input:
    tuple val(template), val(runinfo_json), val(multiqc_json)

    output:
    file('*.html')

    exec:
    def db = new MetadataDB(params.db, log)
    def platform = (runinfo_json.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        run: multiqc_json,
        workflow: workflow,
        platform: platform,
        event: runinfo_json
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
    | OnStartClarityHTML

    Channel.watchPath("$projectDir/assets/*start.groovy", 'create,modify')
    | map { [it, new RunInfofile("$projectDir/assets/testing/runinfo/freezeman.runinfo.example.json", log)] }
    | OnStartFreezemanHTML
}

workflow OnFinishDebug {
    Channel.watchPath("$projectDir/assets/*finish.groovy", 'create,modify')
    | map { [it, new MultiQC("$projectDir/assets/testing/multiqc_data.example.json")] }
    | OnFinishClarityHTML

    Channel.watchPath("$projectDir/assets/*finish.groovy", 'create,modify')
    | map { [it, new RunInfofile("$projectDir/assets/testing/runinfo/freezeman.runinfo.example.json", log), new MultiQC("$projectDir/assets/testing/multiqc_data.example.json")] }
    | OnFinishFreezemanHTML
}

workflow FlagfileDebug {
    Channel.fromPath(params.mgi?.t7?.flags)
    | map { new MgiFlagfile(it) }
    | view { it }
}
