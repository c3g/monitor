import java.nio.file.Path

class MgiSuccessfile {
    String flowcell
    Path path
    Long lastmodified

    MgiSuccessfile(Path path) {
        this.path = path.toAbsolutePath()
        this.lastmodified = path.lastModified()
        this.flowcell = path.toString().split('/')[-1].split('_')[0]
    }

    MgiSuccessfile(String path, String flowcell, Long lastmodified) {
        this.path = path
        this.lastmodified = lastmodified
        this.flowcell = flowcell
    }

    String flowcell() {
        return this.flowcell
    }

    String toString() {
        "${this.flowcellID} | ${this.path}"
    }
}