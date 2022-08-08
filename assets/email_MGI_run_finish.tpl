def nfGeneral = java.text.NumberFormat.getInstance()
def nfPercent = java.text.NumberFormat.getPercentInstance()
nfPercent.setMinimumFractionDigits(1)
Date date = new Date()
def yield = run.generalStats.inject(0) { count, item -> item.value.yield as BigInteger }

yieldUnescaped '<!DOCTYPE html>'
html(lang:'en') {
    head {
        meta('http-equiv':'"Content-Type" content="text/html; charset=utf-8"')
        title("MGI Run finished: ${run.flowcell}")
    }
    body {
        div(style:"font-family: Helvetica, Arial, sans-serif; padding: 30px; max-width: 900px; margin: 0 auto;") {
            h3 "Flowcell: ${run.flowcell}"
            p {
                span "Run processing finished. Full report attached to this email, but also available "
                a href:"https://datahub-297-p25.p.genap.ca/MGI_validation/2022/${run.flowcell}.report.html", "on GenAP"
                span "."
            }
            ul {
                li "Spread: ${run.headerInfo.Spreads}"
                li "Yield assigned to samples: ${nfGeneral.format(yield)} bp"
                li "Instrument: ${run.headerInfo.Instrument}"
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
                    .sort{ it.key }
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
                span workflow.commitId ? "Email generated at ${dateFormat(date)} using monitor at commit ${workflow.commitId}." : "Email generated at ${dateFormat(date)}."
            }
            p(style:"color: #999999; font-size: 12px", "C3G Run Processing.")
        }
    }
}

def dateFormat(date) {
    date.format('yyyy-MM-dd HH:mm:ss z')
}

