#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { Launch as MgiLaunch } from './workflows/mgi/launch'
include { WatchCheckpoints as MgiWatchCheckpoints } from './workflows/mgi/monitor'
include { WatchFinish as MgiWatchFinish } from './workflows/mgi/monitor'

include { FlagfileDebug; OnStartDebug; OnFinishDebug } from './workflows/testing'

workflow Monitor {
    MgiWatchCheckpoints()
    MgiWatchFinish()
}

workflow Launch {
    MgiLaunch()
}

workflow MonitorAndLaunch {
    MgiWatchCheckpoints()
    MgiWatchFinish()
    MgiLaunch()
}

workflow Debug {
    def db = new MetadataDB(params.db, log)
    db.setup()

    Channel.fromPath("$projectDir/assets/testing/clarity.event.example.txt")
    .map { new Eventfile(it, log) }
    .map { db.insert(it) }

    // FlagfileDebug()
    OnStartDebug()
    OnFinishDebug()
}

workflow.onComplete {
    if(params.emailoncrash) {
        def msg = """\
            Pipeline execution summary
            ---------------------------
            Completed at: ${workflow.complete}
            Duration    : ${workflow.duration}
            Success     : ${workflow.success}
            workDir     : ${workflow.workDir}
            exit status : ${workflow.exitStatus}
            """.stripIndent()

        sendMail {
            to 'edouard.henrion@mcgill.ca'
            from 'abacus.genome@mail.mcgill.ca'
            subject 'Alert: Monitor stopped'
            body: msg
        }
    }
}
