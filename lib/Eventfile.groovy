@Grab('com.xlson.groovycsv:groovycsv:1.3')

import static com.xlson.groovycsv.CsvParser.parseCsv

import java.nio.file.Path
import java.nio.file.Files
import java.text.SimpleDateFormat
import org.slf4j.Logger

import nextflow.processor.TaskPath

class Eventfile {
    String text
    String path
    String filename
    Long lastmodified
    Long lastlaunched
    String flowcell
    Logger log

    Eventfile(Path path, Logger log) {
        this.text = path.getText()
        this.filename = path.getFileName()
        this.lastmodified = path.lastModified()
        this.flowcell = this.ContainerName()
        this.log = log
    }

    Eventfile(TaskPath path, Logger log) {
        this.text = path.getText()
        this.filename = path.getFileName()
        this.lastmodified = path.lastModified()
        this.log = log
    }

    Eventfile(String text, String filename, Long lastlaunched, Logger log) {
        this.text = text
        this.filename = filename
        this.lastlaunched = lastlaunched
        this.flowcell = this.ContainerName()
        this.log = log
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

    Date getStartDate() {
        return new Date(this.rows().next()?.'Start Date').format("yyyy-MM-dd")
    }

    def getYear() {
        def format = new SimpleDateFormat("yyyy-MM-dd")
        def date = format.parse(this.rows().next()?.'Start Date')
        return String.valueOf(1900 + date.year)
        // println(date.year)
        // return 1900 + date.year
        // return new Date(this.rows().next()?.'Start Date').format("yyyy-MM-dd").getYear()
    }

    Boolean isMgiT7(sun.nio.fs.UnixPath eventfile) {
        return this.flowcell() ==~ /^E1\d+$/
    }

    Boolean isMgiG400(sun.nio.fs.UnixPath eventfile) {
        return this.flowcell() ==~ /^V3\d+$/
    }

    Boolean isIllumina(sun.nio.fs.UnixPath eventfile) {
        return !(this.isMgiT7() || this.isMgiG400())
    }

    String getPlatform() {
        if (this.isMgiG400()) {
            return "mgig400"
        } else if (this.isMgiT7()) {
            return "mgit7"
        } else if (this.isIllumina()) {
            return "illumina"
        }
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