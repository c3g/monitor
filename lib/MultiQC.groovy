import java.nio.file.Path
import groovy.json.JsonSlurper

class MultiCQ {
    Map data
    String flowcell

    MultiCQ(String path) {
        def file = new File(path)
        this.data = new JsonSlurper().parseText(file.text)
        def config_report_header_info = data?.config_report_header_info
        this.flowcell = config_report_header_info.find { it.containsKey("Run") }.Run
    }

    MultiCQ(Path path) {
        this.data = new JsonSlurper().parseText(path.getText())
        def config_report_header_info = data?.config_report_header_info
        this.flowcell = config_report_header_info.find { it.containsKey("Run") }.Run
    }

    def getGeneralStats() {
        // The generalStats is broken up into an array of maps
        // so were join them together here into a single map.
        this.data['report_general_stats_data'].inject([:]) { result, statmap ->
            statmap.each { key, val ->
                if (result[key]) {
                    result[key] += val
                } else {
                    result[key] = val
                }
            }
            result
        }
    }

    def getHeaderInfo() {
        this.data['config_report_header_info'].inject([:]) { result, map -> result + map }
    }

    String toString() {
        return "MultiQC(${flowcell})"
    }

    String getSeqtype() {
        return this.headerInfo['Seqtype'] ?: 'MGI'
    }
}