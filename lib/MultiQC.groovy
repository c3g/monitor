import java.nio.file.Path
import groovy.json.JsonSlurper

class MultiCQ {
    Map data
    String flowcell

    MultiCQ(Path path) {
        this.data = new JsonSlurper().parseText(path.getText())

        def config_report_header_info = data?.config_report_header_info
        this.flowcell = config_report_header_info.find { it.containsKey("Run") }.Run
    }

    def getGeneralStats() {
        def data = this.data['report_general_stats_data'].first()
        data
    }

    String toString() {
        return "MultiQC(${flowcell})"
    }
}