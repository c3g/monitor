@Grab('com.xlson.groovycsv:groovycsv:1.3')

import static com.xlson.groovycsv.CsvParser.parseCsv

import java.nio.file.Path
import java.nio.file.Files

import nextflow.processor.TaskPath

class Eventfile {
    String text
    String path
    String filename
    Long lastmodified
    Long lastlaunched
    String flowcell

    Eventfile(Path path) {
        this.text = path.getText()
        this.filename = path.getFileName()
        this.lastmodified = path.lastModified()
        this.flowcell = this.ContainerName()
    }

    Eventfile(TaskPath path) {
        this.text = path.getText()
        this.filename = path.getFileName()
        this.lastmodified = path.lastModified()
    }

    Eventfile(String text, String filename, Long lastlaunched) {
        this.text = text
        this.filename = filename
        this.lastlaunched = lastlaunched
        this.flowcell = this.ContainerName()
    }

    def rows() {
        parseCsv(this.text, separator: '\t')
    }

    Boolean alreadyLaunched() {
        this.lastlaunched != null
    }

    Boolean notEmpty() {
        this.rows().size() > 0
    }

    Boolean isEmpty() {
        this.rows().size() == 0
    }

    // TODO: Deprecate this method
    String flowcell() {
        return this.ContainerName()
    }

    String ContainerName() {
        return this.rows().next()?.ContainerName
    }

    Date StartDate() {
        return Date(this.rows().next()?.'Start Date').format("yyyy-MM-dd")
    }

    String year() {
        return this.StartDate.getYear()
    }

    Boolean isMgiT7(sun.nio.fs.UnixPath eventfile) {
        return this.flowcell() ==~ /^E1\d+$/
    }

    String toString() {
        def launched = lastlaunched ? new Date( lastlaunched * 1000 ).format("yyyy-MM-dd'T'HH:mm:ss") : "Unlaunched"
        return "Eventfile(${this.filename}, ${this.ContainerName()}, Launched ${launched})"
    }

    File toTemporaryFile() {
        Path tmpdir = Files.createTempDirectory(null);
        tmpdir.toFile().deleteOnExit();
        File tmpfile = File.createTempFile(flowcell, "_samples.txt", tmpdir)
        tmpfile.deleteOnExit()
        tmpfile.write(this.text)
        tmpfile
    }
}