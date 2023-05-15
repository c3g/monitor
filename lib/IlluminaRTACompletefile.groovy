import java.nio.file.Path

class IlluminaRTACompletefile {
    String flowcell
    Path path
    Long lastmodified
    String seqtype

    IlluminaRTACompletefile(Path path, String type) {
        this.path = path.toAbsolutePath()
        this.lastmodified = path.lastModified()
        def raw_flowcell = path.toString().split('/')[-2].split('_')[-2]
        this.flowcell = raw_flowcell[1..raw_flowcell.size()-1]
        this.seqtype = type
    }

    String flowcell() {
        return this.flowcell
    }

    String toString() {
        "${this.flowcellID} | ${this.path}"
    }
}