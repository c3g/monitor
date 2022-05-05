import java.nio.file.Path
import groovy.json.JsonSlurper

class MgiFlagfile {
    String flowcell
    Path path
    Long lastmodified

    MgiFlagfile(Path path) {
        def ff = new JsonSlurper().parseText(path.getText())
        this.flowcell = ff.slide
        this.path = path.toAbsolutePath()
        this.lastmodified = path.lastModified()
    }

    MgiFlagfile(String path, String flowcell, Long lastmodified) {
        this.flowcell = flowcell
        this.path = path
        this.lastmodified = lastmodified
    }

    String flowcell() {
        return this.flowcell
    }

    String toString() {
        "${this.flowcellID} | ${this.path}"
    }
}