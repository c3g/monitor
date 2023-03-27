@Grab('com.xlson.groovycsv:groovycsv:1.3')

import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.Files

import static com.xlson.groovycsv.CsvParser.parseCsv

process EmailAlertStart {
    executor 'local'

    input:
    val runinfofile

    output:
    val runinfofile

    when:
    !params.nomail

    exec:
    // println runinfofile
    def samples = runinfofile.data.samples
    def platform = (runinfofile.platform == "illumina") ? "Illumina" : "MGI"
    def email_fields = [
        flowcell: runinfofile.flowcell,
        samples: samples,
        platform: platform,
        workflow: workflow
    ]

    def engine = new groovy.text.GStringTemplateEngine()
    def html = new File("$projectDir/assets/email_run_start.html")
    def html_template = engine.createTemplate(html).make(email_fields)

    Path tmpdir = Files.createTempDirectory("runprocessing");
    def tmpfile = new File(tmpdir.toFile(), runinfofile.filename)
    tmpfile.write(runinfofile.data.toString())

    log.debug("New run ${runinfofile.flowcell} | Sending email to '${params.email.onstart}'")

    sendMail {
        to params.email.onstart
        from 'abacus.genome@mail.mcgill.ca'
        attach "$tmpfile"
        subject "Run processing starting - ${runinfofile.flowcell}"

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
    tuple val(runinfofile), path("genpipes")

    output:
    val runinfofile

    script:
    def custom_ini = params?.mgi?.g400?.custom_ini ?: ""
    def genpipes = "\$(realpath genpipes)"
    def splitbarcodeDemux = (runinfofile.platform == "mgit7" && params?.mgi?.t7?.demux) ? "--splitbarcode-demux" : ""
    def flag = (runinfofile.platform == "mgit7") ? "--flag /nb/Research/MGISeq/T7/R1100600200054/flag" : ""
    """
export MUGQIC_INSTALL_HOME_PRIVATE=/lb/project/mugqic/analyste_private
module use \$MUGQIC_INSTALL_HOME_PRIVATE/modulefiles
export MUGQIC_PIPELINES_HOME=${genpipes}

mkdir -p ${params.mgi.outdir}/${runinfofile.flowcell}

cat <<EOF > ${runinfofile.filename}
${runinfofile.data.toString()}
EOF

\$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.py \\
    -c \$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.base.ini ${custom_ini} \\
    --genpipes_file genpipes_submitter.sh \\
    -o ${params.mgi.outdir}/${runinfofile.flowcell} \\
    -j pbs \\
    -l debug \\
    -d /nb/Research/MGISeq/T7/R1100600200054/upload/workspace/${runinfofile.flowcell} \\
    $flag \\
    --run-id ${runinfofile.flowcell} \\
    --no-json \\
    $splitbarcodeDemux \\
    --type ${runinfofile.platform} \\
    -r ${runinfofile.filename} \\
    --force_mem_per_cpu 5G
    """
}

process BeginRunT7 {
    executor 'local'
    module 'mugqic/python/3.10.4'

    input:
    tuple val(runinfofile), path("genpipes")

    output:
    val runinfofile

    script:
    def custom_ini = params?.mgi?.t7?.custom_ini ?: ""
    def genpipes = "\$(realpath genpipes)"
    def splitbarcodeDemux = (runinfofile.platform == "mgit7" && params?.mgi?.t7?.demux) ? "--splitbarcode-demux" : ""
    // def out_dirname = []
    // def outpath = Paths.get(params.mgi.outdir, )
    """
export MUGQIC_INSTALL_HOME_PRIVATE=/lb/project/mugqic/analyste_private
module use \$MUGQIC_INSTALL_HOME_PRIVAT E/modulefiles
export MUGQIC_PIPELINES_HOME=${genpipes}

mkdir -p ${params.mgi.outdir}/${runinfofile.flowcell}

cat <<EOF > ${runinfofile.filename}
${runinfofile.text}
EOF

\$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.py \\
    -c \$MUGQIC_PIPELINES_HOME/pipelines/run_processing/run_processing.base.ini ${custom_ini} \\
    --genpipes_file genpipes_submitter.sh \\
    -o ${params.mgi.outdir}/${runinfofile.flowcell} \\
    -j pbs \\
    -l debug \\
    -d /nb/Research/MGISeq/T7/R1100600200054/upload/workspace/${runinfofile.flowcell} \\
    --flag /nb/Research/MGISeq/T7/R1100600200054/flag \\
    --run-id ${runinfofile.flowcell} \\
    --no-json \\
    $splitbarcodeDemux \\
    --type mgit7 \\
    -r ${runinfofile.filename}
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

    Channel.from(params.commit) | GetGenpipes

    runinfofiles
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
    Channel.fromPath(params.mgi.t7.flags)
    .map { new MgiFlagfile(it) }
    .map { db.insert(it) }

    // New flag files should be stored and then checked to see if we should begin processing
    log.info("Watching for new MGI T7 flag files at '${params.mgi.t7.flags}'")
    Channel.watchPath(params.mgi.t7.flags)
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
    | EmailAlertStart
    | BeginRun
    | map { RunInfofile rinfo -> db.markAsLaunched(rinfo) }
}

workflow MatchRunInfofilesWithIlluminaRuns {
    take:
    runinfofiles

    main:
    def db = new MetadataDB(params.db, log)

    Channel.from(params.commit) | GetGenpipes

    runinfofiles.dump(tag: "illumina_rinf")

    runinfofiles
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