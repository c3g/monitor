// == Introduction == //
// This is an HTML email template that is constructed when MGI runs finish.
// This template used by the EmailAlertFinish process.
// When the template is rendered/instantiated, we pass it two objects:
// - the `run`, which is the MultiQC Groovy object mentioned above
// - the `workflow`, which is the Nextflow workflow object also mentioned above.
// - the `platform`, which is a string extracted from the eventfiles and reformated.
// - the `event`, which is the event file Groovy object of the currentl run
// The `run` object is used throughout, but `workflow` is only used to pull the commitID in the footer.


// == Testing == //
// To test modifications to this template, there is the `Debug` workflow, which looks for changes to
// this file and upon detecting a change, regenerates the template using an example multiqc json file.
// The demo HTML is written to outputs/testing/email/email_MGI_run_finish.html. I'd recommend setting up
// a live watcher so that you can just save the template and the page gets updated in-browser instantly.


// == Helpers == //
// Here we define a couple of helpful variables/function to make the rest of the
// template a little cleaner.
Date now = new Date()
def nfGeneral = java.text.NumberFormat.getInstance()
def yield = run.generalStats.inject(0) { count, item -> item.value.yield as BigInteger }
def nfPercent = java.text.NumberFormat.getPercentInstance()
nfPercent.setMinimumFractionDigits(1)

def dateFormat(date) {
    date.format('yyyy-MM-dd HH:mm:ss z')
}

// == HTML Template == //
// The actual temlate code.
yieldUnescaped '<!DOCTYPE html>'
html(lang:'en') {
    head {
        meta('http-equiv':'"Content-Type" content="text/html; charset=utf-8"')
        title("${platform} Run finished: ${run.run}")
    }
    body {
        div(style:"font-family: Helvetica, Arial, sans-serif; padding: 30px; max-width: 900px; margin: 0 auto;") {
            h3 "Run: ${event.data.run_name} (${run.flowcell})"
            h3 "Folder: ${run.analysis_dir}"
            p {
                span "Run processing finished. Full report attached to this email, but also available "
                a ( href:"https://datahub-297-p25.p.genap.ca/Freezeman_validation/${event.year}/${run.run}.report.html", "on GenAP" )
                span "."
            }
            ul {
                li "Spread: ${run.headerInfo.Spreads}"
                li "Yield assigned to samples: ${nfGeneral.format(yield)} bp"
                li "Instrument: ${run.headerInfo.Instrument}"
            }
            table(style:"box-shadow: 0 0 30px rgba(0, 0, 0, 0.05);margin: 25px 0;font-size: 0.9em;border-collapse: collapse;") {
                tbody {
                    tr(style:"background-color: #009879;color: #ffffff;text-align: left;") {
                        th(style:'padding: 5px 10px', "Project Name")
                        th(style:'padding: 5px 10px', "Samples")
                    }
                    samples.countBy{it.ProjectName ? it.ProjectName : it.project_name}.each { projectname, count -> 
                        tr(style:'border: 2px solid #dddddd;') {
                            td style:"padding: 5px 10px; font-weight: bold", projectname
                            td style:"padding: 5px 10px;", count == 1 ? "${count} sample" : "${count} samples"
                        }
                    }
                    tr(style:'background-color: #666666;color: #ffffff;text-align:left;') {
                        td "Total"
                        td  samples.size() == 1 ? "${samples.size()} sample" : "${samples.size()} samples"
                    }
                }
            }
            table(style:"box-shadow: 0 0 30px rgba(0, 0, 0, 0.05);margin: 25px 0;font-size: 0.9em;border-collapse: collapse;") {
                thead {
                    tr(style:"background-color: #009879;color: #ffffff;text-align: left;") {
                        th(style:'padding: 5px 10px', "Sample Name")
                        th(style:'padding: 5px 10px', "Project")
                        th(style:'padding: 5px 10px', "Clusters")
                        th(style:'padding: 5px 10px', "Yield (bp)")
                        th(style:'padding: 5px 10px', "GC")
                        th(style:'padding: 5px 10px', "Q30 rate")
                    }
                }
                tbody {
                    run
                    .generalStats
                    .sort { it.key }
                    .each {
                        def name = it.key
                        def vals = it.value
                        tr(style:'border: 2px solid #dddddd;') {
                            td style:"padding: 5px 10px; font-weight: bold", name
                            td style:"padding: 5px 10px;", vals['Project']
                            td style:"padding: 5px 10px;", nfGeneral.format(vals['clusters'])
                            td style:"padding: 5px 10px;", nfGeneral.format(vals['yield'])
                            td style:"padding: 5px 10px;", nfPercent.format(vals['gc'])
                            td style:"padding: 5px 10px;", nfPercent.format(vals['q30_rate'])
                        }
                    }
                }
            }
            p(style:"color: #999999; font-size: 12px") {
                span workflow.commitId ? "Email generated at ${dateFormat(now)} using monitor at commit ${workflow.commitId}." : "Email generated at ${dateFormat(now)}."
            }
            p(style:"color: #999999; font-size: 12px", "C3G Run Processing.")
            // p {
            //     span(class:"apple-link", style:"color: #999999; font-size: 12px; text-align: center;") {
            //         a(href:"https://c3g.ca/", style:"text-decoration: none; color: #999999; font-size: 12px; text-align: center;", "C3G Run Processing")
            //     }
            // }
        }
    }
}
