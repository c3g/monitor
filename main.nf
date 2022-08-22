#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { Launch as MgiLaunch } from './workflows/mgi/launch'
include { WatchCheckpoints as MgiWatchCheckpoints } from './workflows/mgi/monitor'
include { WatchFinish as MgiWatchFinish } from './workflows/mgi/monitor'

include { FlagfileDebug; OnFinishDebug } from './workflows/testing'

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
    // FlagfileDebug()
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
            to 'robert.syme@mcgill.ca'
            from 'abacus.genome@mail.mcgill.ca'
            subject 'Alert: Monitor stopped'
            body: msg
        }
    }
}
