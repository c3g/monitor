#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { Launch as ClarityLaunch } from './workflows/clarity/launch'
include { Launch as FreezemanLaunch } from './workflows/freezeman/launch'
include { WatchCheckpoints as ClarityWatchCheckpoints } from './workflows/clarity/monitor'
include { WatchCheckpoints as FreezemanWatchCheckpoints } from './workflows/freezeman/monitor'
include { WatchFinish as ClarityWatchFinish } from './workflows/clarity/monitor'
include { WatchFinish as FreezemanWatchFinish } from './workflows/freezeman/monitor'

include { FlagfileDebug; OnStartDebug; OnFinishDebug } from './workflows/testing'

workflow ClarityMonitor {
    ClarityWatchCheckpoints()
    ClarityWatchFinish()
}

workflow FreezemanMonitor {
    FreezemanWatchCheckpoints()
    FreezemanWatchFinish()
}

workflow Monitor {
    ClarityMonitor()
    FreezemanMonitor()
}

workflow CLaunch {
    ClarityLaunch()
}

workflow FLaunch {
    FreezemanLaunch()
}

workflow Launch {
    CLaunch()
    FLaunch()
}

workflow ClarityMonitorAndLaunch {
    ClarityMonitor()
    CLaunch()
}

workflow FreezemanMonitorAndLaunch {
    FreezemanMonitor()
    FLaunch()
    log.debug("CHECKING: FreezemanMonitorAndLaunch Completed")
}

workflow MonitorAndLaunch {
    FreezemanMonitorAndLaunch()
    ClarityMonitorAndLaunch()
}

workflow Debug {
    def db = new MetadataDB(params.db, log)
    db.setup()

    Channel.fromPath("$projectDir/assets/testing/events/clarity.event.example.txt")
    .map { new Eventfile(it, log) }
    .map { db.insert(it) }

    Channel.fromPath("$projectDir/assets/testing/runinfo/freezeman.runinfo.example.json")
    .map { new RunInfofile(it, log) }
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
