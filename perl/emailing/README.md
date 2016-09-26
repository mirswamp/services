
To send emails to users using templated messages and comma separated lists,
copy this folder to `swa-rws-dt-01` and run 'sendemails name' where name is the
common substring between the template file and email list file. For example, to
send the emails to the students listed in
`email_invitations_Jackson_COSC_504.csv` using the template
`email_template_Jackson_COSC_504.txt`, run `sendemails Jackson_COSC_504`.

Any server with access to `swa-service-1.mirsam.org` and SWAMP's perlbrew
installed should be able to send emails, but swa-rws-dt-01 was chosen because
it is the host from which emails are typically sent in SWAMP.
