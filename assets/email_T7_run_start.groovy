// This template expects two variables to be defined - `flowcell` and `eventfile_rows`.
// The template is instantiated (in the `EmailAlertStart` process) like so:
// email_fields = [flowcell: eventfile.flowcell, eventfile_rows: rows]
// def html_template = engine.createTemplate(html).make(email_fields)
