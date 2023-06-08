@Grab('com.xlson.groovycsv:groovycsv:1.3')

import groovy.text.markup.TemplateConfiguration
import groovy.text.markup.MarkupTemplateEngine

import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.Files

import java.text.SimpleDateFormat

import static com.xlson.groovycsv.CsvParser.parseCsv

process EmailAlertStart {
    executor 'local'
    errorStrategy 'terminate'

    input:
    val(runinfofile)

    output:
    val(runinfofile)

    when:
    !params.nomail

    exec:
    // println runinfofile
    def platform = (runinfofile.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        flowcell: runinfofile.flowcell,
        samples: runinfofile.data.samples,
        platform: platform,
        workflow: workflow
    ]

    TemplateConfiguration config = new TemplateConfiguration()
    MarkupTemplateEngine engine = new MarkupTemplateEngine(config);
    File templateFile = new File("$projectDir/assets/email_run_start.groovy")
    Writable output = engine.createTemplate(templateFile).make(email_fields)

    Path tmpdir = Files.createTempDirectory("runprocessing");
    def tmpfile = new File(tmpdir.toFile(), runinfofile.filename)
    tmpfile.write(runinfofile.text)

    log.debug("New run ${runinfofile.flowcell} | Sending email to '${params.email.onstart}'")

    sendMail {
        to params.email.onstart
        from 'abacus.genome@mail.mcgill.ca'
        attach "$tmpfile"
        subject "Run processing starting - ${runinfofile.flowcell}"

        output.toString()
    }

    tmpfile.delete()
    tmpdir.delete()
}

process GetGenpipes {
    executor 'local'
    errorStrategy 'terminate'
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
    errorStrategy 'terminate'
    module 'mugqic/python/3.10.4'

    input:
    tuple val(runinfofile), path("genpipes")

    output:
    val(runinfofile)

    script:
    def genpipes = "\$(realpath genpipes)"
    def rundate = new SimpleDateFormat("yyMMdd").format(runinfofile.startDate).toString()
    def custom_ini = params?.custom_ini ?: ""
    def rundir = ""
    def outdir = ""
    def splitbarcodeDemux = ""
    def flag = ""
    def seqtype = ""
    
    if (runinfofile.platform == "illumina") {
        rundir = "\$(ls -dt /nb/Research/*/*${runinfofile.flowcell}* | grep -v 'processing' | head -n 1)"
        outdir = params.illumina.outdir
        def db = new MetadataDB(params.db, log)
        seqtype = db.seqType(runinfofile)
    } else if (runinfofile.platform == "mgig400") {
        rundir = "\$(ls -dt /nb/Research/MGISeq/seq[12]/R213040019001[68]/*${runinfofile.flowcell}* | head -n 1)"
        outdir = params.mgi.outdir
        seqtype = "dnbseqg400"
    } else if (runinfofile.platform == "mgit7") {
        rundir = "/nb/Research/MGISeq/T7/R1100600200054/upload/workspace/${runinfofile.flowcell}"
        // splitbarcodeDemux = (params?.mgi?.t7?.demux) ? "--splitbarcode-demux" : ""
        flag = "--flag ${params.mgi.t7.flags}"
        outdir = params.mgi.outdir
        seqtype = "dnbseqt7"
    }

    """
export MUGQIC_INSTALL_HOME_PRIVATE=/lb/project/mugqic/analyste_private
module use \$MUGQIC_INSTALL_HOME_PRIVATE/modulefiles
export MUGQIC_PIPELINES_HOME=${genpipes}

mkdir -p ${outdir}/${rundate}_${runinfofile.instrument}_${runinfofile.flowcell}-${seqtype}

cat <<EOF > ${runinfofile.filename}
${runinfofile.text}
EOF

\$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.py \\
    -c \$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.base.ini ${custom_ini} \\
    --genpipes_file genpipes_submitter.sh \\
    -o ${outdir}/${rundate}_${runinfofile.instrument}_${runinfofile.flowcell}-${seqtype} \\
    -j pbs \\
    -l debug \\
    -d $rundir \\
    $flag \\
    $splitbarcodeDemux \\
    --type ${runinfofile.platform} \\
    -r ${runinfofile.filename} \\
    --force_mem_per_cpu 5G 2> genpipes_submitter.out

bash genpipes_submitter.sh 

cp ${runinfofile.filename} ${outdir}/${rundate}_${runinfofile.instrument}_${runinfofile.flowcell}-${seqtype}/
cp genpipes_submitter.sh ${outdir}/${rundate}_${runinfofile.instrument}_${runinfofile.flowcell}-${seqtype}/
cp genpipes_submitter.out ${outdir}/${rundate}_${runinfofile.instrument}_${runinfofile.flowcell}-${seqtype}/
    """
}

workflow WatchRunInfofiles {
    def db = new MetadataDB(params.db, log)
    db.setup()

    // Watch for new (readable) runinfo files
    log.info("Watching for new Freezeman run info files at '${params.newruninfopath}'")
    Channel.watchPath(params.newruninfopath) |
    branch {
        unreadable: !it.canRead()
        readable: true
            return new RunInfofile(it, log)
    }
    | set { newRunInfofilesRaw }

    newRunInfofilesRaw.readable.dump(tag: "raw_rinf")

    newRunInfofilesRaw.unreadable.map { log.warn ("Cannot read run info file ${it}") }
    newRunInfofilesRaw.readable
    | branch {
        empty: it.isEmpty()
        mgig400: it.isMgiG400()
        mgit7: it.isMgiT7()
        illumina: it.isIllumina()
    }
    | set { newRunInfofiles }

    newRunInfofiles.empty.map { log.warn ("Empty run info file: ${it}") }
    newRunInfofiles.mgig400.map { db.insert(it) }
    newRunInfofiles.mgit7.map { db.insert(it) }
    newRunInfofiles.illumina.map { db.insert(it) }

    newRunInfofiles.illumina.dump(tag:"pre_ill_rinf")

    emit:
    mgit7 = newRunInfofiles.mgit7
    mgig400 = newRunInfofiles.mgig400
    illumina = newRunInfofiles.illumina
}

workflow MatchRunInfofilesWithG400Runs {
    take:
    runinfofiles

    main:
    def db = new MetadataDB(params.db, log)

    // Preexisting success files go directly to the DB.
    Channel.fromPath(params.mgi.g400.success)
    .map { new MgiSuccessfile(it) }
    .map { db.insert(it) }

    // New success files should be stored and then checked to see if we should begin processing
    log.info("Watching for new MGI G400 success files at '${params.mgi.g400.success}'")
    Channel.watchPath(params.mgi.g400.success)
    .map { new MgiSuccessfile(it) }
    .map { sf ->
        db.insert(sf)
        def rinfo = db.latestRunInfofile(sf.flowcell)
        if (rinfo == null) {
            log.debug("New success file (${sf.flowcell}) | No matching runinfo file")
        } else if (rinfo.alreadyLaunched()) {
            log.debug("New success file (${sf.flowcell}) | Latest runinfo file already launched: ${rinfo}")
        } else {
            log.debug("New success file (${sf.flowcell}) | Found a live runinfo file: ${rinfo}")
            return rinfo
        }
    }
    .set { RunInfofilesForRunningFromSuccessfiles }

    runinfofiles
    .map { RunInfofile rinfo -> db.hasSuccessfile(rinfo) ? rinfo : log.debug("New runinfo file (${rinfo.flowcell}) | No matching *_Success.txt file") }
    .set { RunInfofilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    RunInfofilesForRunning
    | mix(RunInfofilesForRunningFromSuccessfiles)
    | combine(GetGenpipes.out)
    | BeginRun
    | EmailAlertStart
    | map { RunInfofile rinfo -> db.markAsLaunched(rinfo) }
}

workflow MatchRunInfofilesWithT7Runs {
    take:
    runinfofiles

    main:
    def db = new MetadataDB(params.db, log)

    // Preexisting flag files go directly to the DB.
    Channel.fromPath("${params.mgi.t7.flags}/*.json")
    .map { new MgiFlagfile(it) }
    .map { db.insert(it) }

    // New flag files should be stored and then checked to see if we should begin processing
    log.info("Watching for new MGI T7 flag files in '${params.mgi.t7.flags}'")
    Channel.watchPath("${params.mgi.t7.flags}/*.json")
    .map { new MgiFlagfile(it) }
    .map { ff ->
        db.insert(ff)
        def rinfo = db.latestRunInfofile(ff.flowcell)
        if (rinfo == null) {
            log.debug("New flag file (${ff.flowcell}) | No matching runinfo file")
        } else if(rinfo.alreadyLaunched()) {
            log.debug("New flag file (${ff.flowcell}) | Latest runinfo file already launched: ${rinfo}")
        } else {
            log.debug("New flag file (${ff.flowcell}) | Found a live runinfo file: ${rinfo}")
            return rinfo
        }
    }
    .set { RunInfofilesForRunningFromFlagfiles }

    runinfofiles
    .map { RunInfofile rinfo -> db.hasFlagfile(rinfo) ? rinfo : log.debug("New runinfo file (${rinfo.flowcell}) | No matching flag file") }
    .set { RunInfofilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    RunInfofilesForRunning
    | mix(RunInfofilesForRunningFromFlagfiles)
    | combine(GetGenpipes.out)
    | BeginRun
    | EmailAlertStart
    | map { RunInfofile rinfo -> db.markAsLaunched(rinfo) }
}

workflow MatchRunInfofilesWithIlluminaRuns {
    take:
    runinfofiles

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
        def rinfo = db.latestRunInfofile(rf.flowcell)
        if (rinfo == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching runinfo file")
        } else if (rinfo.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest runinfo file already launched: ${rinfo}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live runinfo file: ${rinfo}")
            return rinfo
        }
    }
    .set { RunInfofilesForRunningFromMiseq }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.hiseqx}'")
    Channel.watchPath(params.illumina.hiseqx)
    .map { new IlluminaRTACompletefile(it, "hiseqx") }
    .map { rf ->
        db.insert(rf)
        def rinfo = db.latestRunInfofile(rf.flowcell)
        if (rinfo == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching runinfo file")
        } else if (rinfo.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest runinfo file already launched: ${rinfo}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live runinfo file: ${rinfo}")
            return rinfo
        }
    }
    .set { RunInfofilesForRunningFromHiseqX }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.novaseq}'")
    Channel.watchPath(params.illumina.novaseq)
    .map { new IlluminaRTACompletefile(it, "novaseq") }
    .map { rf ->
        db.insert(rf)
        def rinfo = db.latestRunInfofile(rf.flowcell)
        if (rinfo == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching runinfo file")
        } else if (rinfo.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest runinfo file already launched: ${rinfo}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live runinfo file: ${rinfo}")
            return rinfo
        }
    }
    .set { RunInfofilesForRunningFromNovaseq }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.iseq1}'")
    Channel.watchPath(params.illumina.iseq1)
    .map { new IlluminaRTACompletefile(it, "iseq") }
    .map { rf ->
        db.insert(rf)
        def rinfo = db.latestRunInfofile(rf.flowcell)
        if (rinfo == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching runinfo file")
        } else if (rinfo.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest runinfo file already launched: ${rinfo}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live runinfo file: ${rinfo}")
            return rinfo
        }
    }
    .set { RunInfofilesForRunningFromISeq1 }

    log.info("Watching for new Illumina RTAComplete files at '${params.illumina.iseq2}'")
    Channel.watchPath(params.illumina.iseq2)
    .map { new IlluminaRTACompletefile(it, "iseq") }
    .map { rf ->
        db.insert(rf)
        def rinfo = db.latestRunInfofile(rf.flowcell)
        if (rinfo == null) {
            log.debug("New RTAComplete file (${rf.flowcell}) | No matching runinfo file")
        } else if (rinfo.alreadyLaunched()) {
            log.debug("New RTAComplete file (${rf.flowcell}) | Latest runinfo file already launched: ${rinfo}")
        } else {
            log.debug("New RTAComplete file (${rf.flowcell}) | Found a live runinfo file: ${rinfo}")
            return rinfo
        }
    }
    .set { RunInfofilesForRunningFromISeq2 }

    RunInfofilesForRunningFromMiseq
    | mix(RunInfofilesForRunningFromHiseqX)
    | mix(RunInfofilesForRunningFromNovaseq)
    | mix(RunInfofilesForRunningFromISeq1)
    | mix(RunInfofilesForRunningFromISeq2)
    | set { RunInfofilesForRunningFromRTACompletefiles }

    runinfofiles.dump(tag: "illumina_rinf")

    runinfofiles
    .map { RunInfofile rinfo -> db.hasRTAcompletefile(rinfo) ? rinfo : log.debug("New runinfo file (${rinfo.flowcell}) | No matching RTAComplete file") }
    .set { RunInfofilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    RunInfofilesForRunning
    | mix(RunInfofilesForRunningFromRTACompletefiles)
    | combine(GetGenpipes.out)
    | BeginRun
    | EmailAlertStart
    | map { RunInfofile rinfo -> db.markAsLaunched(rinfo) }
}

workflow Launch {
    WatchRunInfofiles()
    MatchRunInfofilesWithG400Runs(WatchRunInfofiles.out.mgig400)
    MatchRunInfofilesWithT7Runs(WatchRunInfofiles.out.mgit7)
    MatchRunInfofilesWithIlluminaRuns(WatchRunInfofiles.out.illumina)
}
