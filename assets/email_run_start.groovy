// == Introduction == //
// This template expects three variables to be defined - `flowcell`, `samples` and `platofrm`.
// The template is instantiated (in the `EmailAlertStart` process) like so:
// email_fields = [flowcell: eventfile.flowcell, samples: rows, platform: platform]
// def html_template = engine.createTemplate(html).make(email_fields)

// == Testing == //
// To test modifications to this template, there is the `Debug` workflow, which looks for changes to
// this file and upon detecting a change, regenerates the template using an example multiqc json file.
// The demo HTML is written to outputs/testing/email/email_MGI_run_finish.html. I'd recommend setting up
// a live watcher so that you can just save the template and the page gets updated in-browser instantly.

// == Helpers == //
// Here we define a couple of helpful variables/function to make the rest of the
// template a little cleaner.
Date now = new Date()

def dateFormat(date) {
    date.format('yyyy-MM-dd HH:mm:ss z')
}

// == HTML Template == //
// The actual temlate code.
yieldUnescaped '<!DOCTYPE html>'
html(lang:'en') {
    head {
        meta('http-equiv':'"Content-Type" content="text/html; charset=utf-8"')
        title("${platform} Run started - Flowcell ${flowcell}")
    }
    body {
        div(style:"font-family: Helvetica, Arial, sans-serif; padding: 30px; max-width: 900px; margin: 0 auto;") {
            h2 "New run processing started : ${flowcell}"
            p {
                span "This is an automated message sent from the run processing event monitor."
            }
            p {
                span "Run processing has started for new ${platform} run on flowcell: ${flowcell}. "
            }
            p {
                span "Freezeman Run Info file used is attached."
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
            p(style:"color: #999999; font-size: 12px") {
                span workflow.commitId ? "Email generated at ${dateFormat(now)} using monitor at commit ${workflow.commitId}." : "Email generated at ${dateFormat(now)}."
            }
            p {
                span(class:"apple-link", style:"color: #999999; font-size: 12px; text-align: center;") {
                    a(href:"https://c3g.ca/", style:"text-decoration: none; color: #999999; font-size: 12px; text-align: center;", "C3G Run Processing")
                }
            }
        }
    }
}


// <html>

//  <head>
//      <meta charset="utf-8">
//      <meta http-equiv="X-UA-Compatible" content="IE=edge">
//      <meta name="viewport" content="width=device-width, initial-scale=1">

//      <meta name="description" content="New run notification.">
//      <title>T7 Flowcell ${flowcell}</title>
//  </head>

//  <body>
//      <div style="font-family: Helvetica, Arial, sans-serif; padding: 30px; max-width: 800px; margin: 0 auto;">

//          <h2>New run processing started</h2>
//          <h3>Flowcell: <span style='font-weight: bold'>$flowcell</span></h3>

//          <table
//              style="width:100%; max-width:100%; border-spacing: 0; border-collapse: collapse; border:0; margin-bottom: 30px;">
//              <tbody style="border-bottom: 1px solid #ddd;">
//                  <tr>
//                      <th
//                          style='text-align:left; padding: 8px 0; line-height: 1.42857143; vertical-align: top; border-top: 1px solid #ddd; border-bottom: 1px solid #ddd;'>
//                          Project Name</th>
//                      <th
//                          style='text-align:left; padding: 8px; line-height: 1.42857143; vertical-align: top; border-top: 1px solid #ddd; border-bottom: 1px solid #ddd;'>
//                          Samples</th>
//                  </tr>
//                  <% samples.countBy{it.ProjectName}.each { projectname, count -> %>
//                      <tr style='line-height: 1.42857143; vertical-align: top; '>
//                          <td>$projectname</td>
//                          <td>$count ${count == 1 ? "sample" : "samples"}</td>
//                      </tr>
//                      <% } %>
//                          <tr
//                              style='text-align:left; padding: 8px; line-height: 1.42857143; vertical-align: top; border-top: 1px solid #ddd; border-bottom: 1px solid #ddd;'>
//                              <td>Total</td>
//                              <td>${samples.size()} ${samples.size() == 1 ? "sample" : "samples"}</td>
//                          </tr>
//              </tbody>
//          </table>

//          <p>
//              <span class="apple-link" style="color: #999999; font-size: 12px; text-align: center;"><a
//                      href="https://c3g.ca/"
//                      style="text-decoration: none; color: #999999; font-size: 12px; text-align: center;">C3G
//                      Run Processing</a>
//          </p>

//      </div>

//  </body>

//  </html>