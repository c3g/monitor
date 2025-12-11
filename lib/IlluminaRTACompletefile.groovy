import java.nio.file.Path

class IlluminaRTACompletefile {
    String flowcell
    Path path
    Long lastmodified
    String seqtype

    IlluminaRTACompletefile(Path path, String type) {
        this.path = path.toAbsolutePath()
        this.lastmodified = path.lastModified()
        this.seqtype = type
        def raw_flowcell
        if ( type == "novaseqx" ) {
            raw_flowcell = path.toString().split('/')[-2].split('_')[3]
        } else if ( type == "miseq" ) {
            raw_flowcell = path.toString().split('/')[-2].split('-')[-1]
        } else {
            raw_flowcell = path.toString().split('/')[-2].split('_')[-2]
        }
        this.flowcell = raw_flowcell[1..raw_flowcell.size()-1]
    }

    String flowcell() {
        return this.flowcell
    }

    String toString() {
        "${this.flowcellID} | ${this.path}"
    }
}
