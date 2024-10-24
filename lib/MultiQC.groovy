import java.nio.file.Path
import groovy.json.JsonSlurper
import groovy.json.JsonParserType
import java.text.SimpleDateFormat

class MultiQC {
    Map data
    String flowcell
    String run
    String analysis_dir

    MultiQC(String path) {
        def file = new File(path)
        def jsonSlurper = new JsonSlurper().setType( JsonParserType.LAX )
        this.data = jsonSlurper.parseText(file.text)
        this.analysis_dir = data?.config_analysis_dir
        def config_report_header_info = data?.config_report_header_info
        this.flowcell = config_report_header_info.find { it.containsKey("Flowcell") }.Flowcell
        this.run = config_report_header_info.find { it.containsKey("Run") }.Run
    }

    MultiQC(Path path) {
        def jsonSlurper = new JsonSlurper().setType( JsonParserType.LAX )
        this.data = jsonSlurper.parseText(path.getText())
        this.analysis_dir = data?.config_analysis_dir
        def config_report_header_info = data?.config_report_header_info
        this.flowcell = config_report_header_info.find { it.containsKey("Flowcell") }.Flowcell
        this.run = config_report_header_info.find { it.containsKey("Run") }.Run
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

    def getYear() {
        def format = new SimpleDateFormat("yyMMdd")
        def date = format.parse(this.data['config_analysis_dir'][0].tokenize('_').first())
        return 1900 + date.year
    }

    def getHeaderInfo() {
        this.data['config_report_header_info'].inject([:]) { result, map -> result + map }
    }

    String toString() {
        return "MultiQC(${run})"
    }

    String getSeqtype() {
        return this.headerInfo['Seqtype'] ?: 'MGI'
    }
}
