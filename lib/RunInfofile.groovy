@Grab('com.xlson.groovycsv:groovycsv:1.3')

import static com.xlson.groovycsv.CsvParser.parseCsv

import java.nio.file.Path
import java.nio.file.Files
import java.text.SimpleDateFormat
import org.slf4j.Logger

import nextflow.processor.TaskPath

import groovy.json.JsonSlurper

class RunInfofile {
    Map data
    String path
    String filename
    Long lastmodified
    Long lastlaunched
    String flowcell
    Logger log

    RunInfofile(String path, Logger log) {
        def file = new File(path)
        this.data = new JsonSlurper().parseText(file.text)
        this.filename = file.getName()
        this.lastmodified = file.lastModified()
        this.flowcell = this.ContainerName()
        this.log = log
    }

    RunInfofile(Path path, Logger log) {
        this.data = new JsonSlurper().parseText(path.getText())
        this.filename = path.getFileName()
        this.lastmodified = path.lastModified()
        this.flowcell = this.ContainerName()
        this.log = log
    }

    RunInfofile(TaskPath path, Logger log) {
        this.data = new JsonSlurper().parseText(path.getText())
        this.filename = path.getFileName()
        this.lastmodified = path.lastModified()
        this.flowcell = this.ContainerName()
        this.log = log
    }

    RunInfofile(String data, String filename, Long lastlaunched, Logger log) {
        this.data = new JsonSlurper().parseText(data)
        this.filename = filename
        this.lastlaunched = lastlaunched
        this.flowcell = this.ContainerName()
        this.log = log
    }

    Boolean alreadyLaunched() {
        this.lastlaunched != null
    }

    Boolean notEmpty() {
        this.data['samples'].size() > 0
    }

    Boolean isEmpty() {
        this.data['samples'].size() == 0
    }

    // TODO: Deprecate this method
    String flowcell() {
        return this.ContainerName()
    }

    String ContainerName() {
        return this.data['container_barcode']
    }

    Date getStartDate() {
        return new Date(this.data['run_start_date']).format("yyyy-MM-dd")
    }

    def getYear() {
        def format = new SimpleDateFormat("yyyy-MM-dd")
        def date = format.parse(this.data['run_start_date'])
        return String.valueOf(1900 + date.year)
    }

    Boolean isMgiT7(sun.nio.fs.UnixPath runinfofile) {
        return this.flowcell() ==~ /^E1\d+$/
    }

    Boolean isMgiG400(sun.nio.fs.UnixPath runinfofile) {
        return this.flowcell() ==~ /^V3\d+$/
    }

    Boolean isIllumina(sun.nio.fs.UnixPath runinfofile) {
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
        return "RunInfofile(${this.filename}, ${this.ContainerName()}, Launched ${launched})"
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