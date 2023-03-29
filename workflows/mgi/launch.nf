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

    def email_fields = [
        flowcell: eventfile.flowcell,
        eventfile_rows: rows,
    ]

    def engine = new groovy.text.GStringTemplateEngine()
    def html = new File("$projectDir/assets/email_T7_run_start.html")
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
        git clone https://ehenrion@bitbucket.org/mugqic/genpipes.git genpipes
        cd genpipes
        git checkout $commit
        """
}

process BeginRunT7 {
    executor 'local'
    module 'mugqic/python/3.10.4'

    input:
    tuple val(eventfile), path("genpipes")

    output:
    val eventfile

    script:
    def custom_ini = params?.mgi?.t7?.custom_ini ?: ""
    def genpipes = "\$(realpath genpipes)"
    def splitbarcodeDemux = (eventfile.platform == "mgit7" && params?.mgi?.t7?.demux) ? "--splitbarcode-demux" : ""
    // def out_dirname = []
    // def outpath = Paths.get(params.mgi.outdir, )
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
    --flag /nb/Research/MGISeq/T7/R1100600200054/flag \\
    --run-id ${eventfile.flowcell} \\
    --no-json \\
    $splitbarcodeDemux \\
    --type mgit7 \\
    -r ${eventfile.filename}
    """
}

workflow WatchEventfiles {
    def db = new MetadataDB(params.db, log)
    db.setup()

    // Watch for new (readable) eventfiles
    Channel.watchPath(params.neweventpath).branch {
        unreadable: !it.canRead()
        readable: true
            return new Eventfile(it)
    }.set{ newEventfilesRaw }

    newEventfilesRaw.unreadable.map { log.warn ("Cannot read event file ${it}") }
    newEventfilesRaw.readable.branch {
        empty: it.isEmpty()
        mgit7: it.isMgiT7()
    }.set{ newEventfiles }

    newEventfiles.empty.map { log.warn ("Empty event file: ${it}") }

    emit:
    mgit7 = newEventfiles.mgit7
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
            log.debug("New flagfile (${ff.flowcell}) | No matching eventfile")
        } else if(evt.alreadyLaunched()) {
            log.debug("New flagfile (${ff.flowcell}) | Latest eventfile already launched: ${evt}")
        } else {
            log.debug("New flagfile (${ff.flowcell}) | Found a live event file: ${evt}")
            return evt
        }
    }
    .set { EventfilesForRunningFromFlagfiles }

    eventfiles
    .map { Eventfile evt -> db.hasFlagfile(evt) ? evt : log.debug("New eventfile (${evt.flowcell}) | No matching flagfile") }
    .set { EventfilesForRunning }

    Channel.from(params.commit) | GetGenpipes

    EventfilesForRunning
    | mix(EventfilesForRunningFromFlagfiles)
    | combine(GetGenpipes.out)
    | BeginRunT7
    | EmailAlertStart
    | map { Eventfile evt -> db.markAsLaunched(evt) }
}


workflow Launch {
    WatchEventfiles()
    MatchEventfilesWithT7Runs(WatchEventfiles.out.mgit7)
}
