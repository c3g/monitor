import java.nio.file.Path
import groovy.json.JsonSlurper
import java.text.SimpleDateFormat

class RunValidationReport {
    Map data
    String flowcell
    String run

    RunValidationReport(String path) {
        def file = new File(path)
        this.data = new JsonSlurper().parseText(file.text)
        def config_report_header_info = data?.config_report_header_info
        this.flowcell = config_report_header_info.find { it.containsKey("Flowcell") }.Flowcell
        this.run = config_report_header_info.find { it.containsKey("Run") }.Run
    }

    RunValidationReport(Path path) {
        this.data = new JsonSlurper().parseText(path.getText())
        def config_report_header_info = data?.config_report_header_info
        this.flowcell = config_report_header_info.find { it.containsKey("Flowcell") }.Flowcell
        this.run = config_report_header_info.find { it.containsKey("Run") }.Run
    }

    this.data['']
}