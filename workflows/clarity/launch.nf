@Grab('com.xlson.groovycsv:groovycsv:1.3')

import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.Files

import static com.xlson.groovycsv.CsvParser.parseCsv

process EmailAlertStart {
    executor 'local'

    input:
    val eventfile

    output:
    val eventfile

    when:
    !params.nomail

    exec:
    def rows = parseCsv(eventfile.text, separator: '\t').collect()
    def platform = (eventfile.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        flowcell: eventfile.flowcell,
        eventfile_rows: rows,
        platform: platform,
        workflow: workflow
    ]

    def engine = new groovy.text.GStringTemplateEngine()
    def html = new File("$projectDir/assets/email_run_start.html")
    def html_template = engine.createTemplate(html).make(email_fields)

    Path tmpdir = Files.createTempDirectory("runprocessing");
    def tmpfile = new File(tmpdir.toFile(), eventfile.filename)
    tmpfile.write(eventfile.text)

    log.debug("New run ${eventfile.flowcell} | Sending email to '${params.email.onstart}'")

    sendMail {
        to params.email.onstart
        from 'abacus.genome@mail.mcgill.ca'
        attach "$tmpfile"
        subject "Run processing starting - ${eventfile.flowcell}"

        html_template.toString()
    }

    tmpfile.delete()
    tmpdir.delete()
}

process GetGenpipes {
    input:
    val(commit)

    output:
    path("genpipes")

    script:
    if (params.genpipes)
        """
        ln -s ${params.genpipes} genpipes
        """
    else
        """
        git clone git@bitbucket.org:mugqic/genpipes.git genpipes
        cd genpipes
        git checkout $commit
        """
}

process BeginRun {
    executor 'local'
    module 'mugqic/python/3.10.4'

    input:
    tuple val(eventfile), path("genpipes")

    output:
    val eventfile

    script:
    def custom_ini = params?.mgi?.g400?.custom_ini ?: ""
    def genpipes = "\$(realpath genpipes)"
    def splitbarcodeDemux = (eventfile.platform == "mgit7" && params?.mgi?.t7?.demux) ? "--splitbarcode-demux" : ""
    def flag = (eventfile.platform == "mgit7") ? "--flag /nb/Research/MGISeq/T7/R1100600200054/flag" : ""
    """
export MUGQIC_INSTALL_HOME_PRIVATE=/lb/project/mugqic/analyste_private
module use \$MUGQIC_INSTALL_HOME_PRIVATE/modulefiles
export MUGQIC_PIPELINES_HOME=${genpipes}

mkdir -p ${params.mgi.outdir}/${eventfile.flowcell}

cat <<EOF > ${eventfile.filename}
${eventfile.text}
EOF

\$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.py \\
    -c \$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.base.ini ${custom_ini} \\
    --genpipes_file genpipes_submitter.sh \\
    -o ${params.mgi.outdir}/${eventfile.flowcell} \\
    -j pbs \\
    -l debug \\
    -d /nb/Research/MGISeq/T7/R1100600200054/upload/workspace/${eventfile.flowcell} \\
    $flag \\
    --run-id ${eventfile.flowcell} \\
    --no-json \\
    $splitbarcodeDemux \\
    --type ${eventfile.platform} \\
    -r ${eventfile.filename} \\
    --force_mem_per_cpu 5G
    """
}

workflow WatchEventfiles {
    def db = new MetadataDB(params.db, log)
    db.setup()

    // Watch for new (readable) eventfiles
    log.info("Watching for new Clarity event files at '${params.neweventpath}'")
    Channel.watchPath(params.neweventpath)
    | branch {
        unreadable: !it.canRead()
        readable: true
            return new Eventfile(it, log)
    }
    | set{ newEventfilesRaw }

    newEventfilesRaw.unreadable.map { log.warn ("Cannot read event file ${it}") }
    newEventfilesRaw.readable
    | branch {
        empty: it.isEmpty()
        mgig400: it.isMgiG400()
        mgit7: it.isMgiT7()
        illumina: it.isIllumina()
    }
    | set { newEventfiles }

    newEventfiles.empty.map { log.warn ("Empty event file: ${it}") }
    newEventfiles.mgig400.map { db.insert(it) }
    newEventfiles.mgit7.map { db.insert(it) }
    newEventfiles.illumina.map { db.insert(it) }

    emit:
    mgit7 = newEventfiles.mgit7
    mgig400 = newEventfiles.mgig400
    illumina = newEventfiles.illumina
}

workflow MatchEventfilesWithG400Runs {
    take:
    eventfiles

    main:
    def db = new MetadataDB(params.db, log)

    Channel.from(params.commit) | GetGenpipes

    eventfiles
    | combine(GetGenpipes.out)
    | BeginRun
    | EmailAlertStart
    | map { Eventfile evt -> db.markAsLaunched(evt) }
}

workflow MatchEventfilesWithT7Runs {
    take:
    eventfiles

    main:
    def db = new MetadataDB(params.db, log)

    // Preexisting flag files go directly to the DB.
    Channel.fromPath(params.mgi.t7.flags)
    .map { new MgiFlagfile(it) }
    .map { db.insert(it) }

    // New flag files should be stored and then checked to see if we should begin processing
    log.info("Watching for new MGI T7 flag files at '${params.mgi.t7.flags}'")
    Channel.watchPath(params.mgi.t7.flags)
    .map { new MgiFlagfile(it) }
    .map { ff ->
        db.insert(ff)
        def evt = db.latestEventfile(ff.flowcell)
        if (evt == null) {
            log.debug("New flag file (${ff.flowcell}) | No matching event file")
        } else if(evt.alreadyLaunched()) {
            log.debug("New flag file (${ff.flowcell}) | Latest event file already launched: ${evt}")
        } else {
            log.debug("New flag file (${ff.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromFlagfiles }

    eventfiles
    .map { Eventfile evt -> db.hasFlagfile(evt) ? evt : log.debug("New event file (${evt.flowcell}) | No matching flag file") }
    .set { EventfilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    EventfilesForRunning
    | mix(EventfilesForRunningFromFlagfiles)
    | combine(GetGenpipes.out)
    | BeginRun
    | EmailAlertStart
    | map { Eventfile evt -> db.markAsLaunched(evt) }
}

workflow MatchEventfilesWithIlluminaRuns {
    take:
    eventfiles

    main:
    def db = new MetadataDB(params.db, log)

    Channel.from(params.commit) | GetGenpipes

    eventfiles
    | combine(GetGenpipes.out)
    | BeginRun
    | EmailAlertStart
    | map { Eventfile evt -> db.markAsLaunched(evt) }
}

workflow Launch {
    WatchEventfiles()
    MatchEventfilesWithG400Runs(WatchEventfiles.out.mgig400)
    MatchEventfilesWithT7Runs(WatchEventfiles.out.mgit7)
    MatchEventfilesWithIlluminaRuns(WatchEventfiles.out.illumina)
}