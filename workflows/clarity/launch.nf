@Grab('com.xlson.groovycsv:groovycsv:1.3')

import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.Files

import java.text.SimpleDateFormat

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
    def genpipes = "\$(realpath genpipes)"
    def rundate = new SimpleDateFormat("yyMMdd").format(eventfile.startDate).toString()
    def rundir = ""
    def outdir = ""
    def splitbarcodeDemux = ""
    def flag = ""
    def custom_ini = ""
    def seqtype = ""

    if (eventfile.platform == "illumina") {
        rundir = "\$(ls -dt /nb/Research/*/*${eventfile.flowcell}* | head -n 1)"
        outdir = params.illumina.outdir
        def db = new MetadataDB(params.db, log)
        seqtype = db.seqType(eventfile)
    } else if (eventfile.platform == "mgig400") {
        rundir = "\$(ls -dt /nb/Research/MGISeq/seq[12]/R213040019001[68]/*${eventfile.flowcell}* | head -n 1)"
        outdir = params.mgi.outdir
        seqtype = "dnbseqg400"
    } else if (eventfile.platform == "mgit7") {
        rundir = "/nb/Research/MGISeq/T7/R1100600200054/upload/workspace/${eventfile.flowcell}"
        splitbarcodeDemux = (params?.mgi?.t7?.demux) ? "--splitbarcode-demux" : ""
        flag = "--flag /nb/Research/MGISeq/T7/R1100600200054/flag"
        custom_ini = params?.mgi?.t7?.custom_ini ?: ""
        outdir = params.mgi.outdir
        seqtype = "dnbseqt7"
    }
    """
export MUGQIC_INSTALL_HOME_PRIVATE=/lb/project/mugqic/analyste_private
module use \$MUGQIC_INSTALL_HOME_PRIVATE/modulefiles
export MUGQIC_PIPELINES_HOME=${genpipes}

mkdir -p ${outdir}/${eventfile.flowcell}

cat <<EOF > ${eventfile.filename}
${eventfile.text}
EOF

\$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.py \\
    -c \$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.base.ini ${custom_ini} \\
    --genpipes_file genpipes_submitter.sh \\
    -o ${outdir}/${rundate}_${eventfile.flowcell} \\
    -j pbs \\
    -l debug \\
    -d $rundir \\
    $flag \\
    --no-json \\
    $splitbarcodeDemux \\
    --type ${eventfile.platform} \\
    -r ${eventfile.filename} \\
    --force_mem_per_cpu 5G

bash genpipes_submitter.sh

cp ${eventfile.filename} ${outdir}/${rundate}_${eventfile.flowcell}-${seqtype}
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

    // Preexisting success files go directly to the DB.
    Channel.fromPath(params.mgi.g400.success)
    .map { new MgiSuccessfile(it) }
    .map { db.insert(it) }

    // New flag files should be stored and then checked to see if we should begin processing
    log.info("Watching for new MGI G400 success files at '${params.mgi.g400.success}'")
    Channel.watchPath(params.mgi.g400.success)
    .map { new MgiSuccessfile(it) }
    .map { sf ->
        db.insert(sf)
        def evt = db.latestEventfile(sf.flowcell)
        if (evt == null) {
            log.debug("New success file (${sf.flowcell}) | No matching event file")
        } else if(evt.alreadyLaunched()) {
            log.debug("New success file (${sf.flowcell}) | Latest event file already launched: ${evt}")
        } else {
            log.debug("New success file (${sf.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromSuccessfiles }

    eventfiles
    .map { Eventfile evt -> db.hasSuccessfile(evt) ? evt : log.debug("New event file (${evt.flowcell}) | No matching success file") }
    .set { EventfilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    EventfilesForRunning
    | mix(EventfilesForRunningFromSuccessfiles)
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

    // Preexisting RTAComplete files go directly to the DB.
    // Miseq
    Channel.fromPath(params.illumina.miseq)
    .map { new IlluminaRTACompletefile(it, "miseq") }
    .map { db.insert(it) }
    // hiseqX
    Channel.fromPath(params.illumina.hiseqx)
    .map { new IlluminaRTACompletefile(it, "hiseqx") }
    .map { db.insert(it) }
    // Novaseq
    Channel.fromPath(params.illumina.novaseq)
    .map { new IlluminaRTACompletefile(it, "novaseq") }
    .map { db.insert(it) }
    // iSeq
    Channel.fromPath(params.illumina.iseq1)
    .map { new IlluminaRTACompletefile(it, "iseq") }
    .map { db.insert(it) }
    // iSeq (another one)
    Channel.fromPath(params.illumina.iseq2)
    .map { new IlluminaRTACompletefile(it, "iseq") }
    .map { db.insert(it) }

    // New RTAComplete files should be stored and then checked to see if we should begin processing
    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.miseq}'")
    Channel.watchPath(params.illumina.miseq)
    .map { new IlluminaRTACompletefile(it, "miseq") }
    .map { rf ->
        db.insert(rf)
        def evt = db.latestEventfile(rf.flowcell)
        if (evt == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching event file")
        } else if (evt.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest event file already launched: ${evt}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromMiseq }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.hiseqx}'")
    Channel.watchPath(params.illumina.hiseqx)
    .map { new IlluminaRTACompletefile(it, "hiseqx") }
    .map { rf ->
        db.insert(rf)
        def evt = db.latestEventfile(rf.flowcell)
        if (evt == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching event file")
        } else if (evt.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest event file already launched: ${evt}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromHiseqX }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.novaseq}'")
    Channel.watchPath(params.illumina.novaseq)
    .map { new IlluminaRTACompletefile(it, "novaseq") }
    .map { rf ->
        db.insert(rf)
        def evt = db.latestEventfile(rf.flowcell)
        if (evt == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching event file")
        } else if (evt.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest event file already launched: ${evt}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromNovaseq }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.iseq1}'")
    Channel.watchPath(params.illumina.iseq1)
    .map { new IlluminaRTACompletefile(it, "iseq") }
    .map { rf ->
        db.insert(rf)
        def evt = db.latestEventfile(rf.flowcell)
        if (evt == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching event file")
        } else if (evt.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest event file already launched: ${evt}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromISeq1 }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.iseq2}'")
    Channel.watchPath(params.illumina.iseq2)
    .map { new IlluminaRTACompletefile(it, "iseq") }
    .map { rf ->
        db.insert(rf)
        def evt = db.latestEventfile(rf.flowcell)
        if (evt == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching event file")
        } else if (evt.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest event file already launched: ${evt}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromISeq2 }

    EventfilesForRunningFromMiseq
    | mix(EventfilesForRunningFromHiseqX)
    | mix(EventfilesForRunningFromNovaseq)
    | mix(EventfilesForRunningFromISeq1)
    | mix(EventfilesForRunningFromISeq2)
    | set { EventfilesForRunningFromRTACompletefiles }


    eventfiles
    .map { Eventfile evt -> db.hasRTAcompletefile(evt) ? evt : log.debug("New event file (${evt.flowcell}) | No matching RTAComplete file") }
    .set { EventfilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    EventfilesForRunning
    | mix(EventfilesForRunningFromRTACompletefiles)
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