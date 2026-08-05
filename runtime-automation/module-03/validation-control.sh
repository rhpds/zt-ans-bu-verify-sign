#!/bin/sh
echo "Validated module called module-03" >> /tmp/progress.log

tower-cli config verify_ssl false
tower-cli login admin --password ansible123!


if [[ ! -f "/home/rhel/ansible-sign-demo/MANIFEST.in" ]]; then
    fail-message "MANIFEST.in was not created"
elif [[ ! -f "/home/rhel/ansible-sign-demo/.ansible-sign/sha256sum.txt" ]]; then
    fail-message "Local project is not signed using 'ansible-sign'"
elif ! tower-cli credential list -f json | jq -e '.results[] | select(.name | match("ansible-sign";"i"))' ; then
    fail-message "'ansible-sign' credential was not created in automation controller"
elif ! tower-cli project list -f json | jq -e '.results[] | select(.name | match("Signed Project";"i"))'; then
    fail-message "Signed Project was not created in automation controller"
elif ! tower-cli project list -f json | jq -e '.results[].summary_fields.signature_validation_credential | select( . != null ) |select(.name | match("ansible-sign";"i"))'; then
    fail-message "GPG key credential was not attached to the project for validation"
elif ! tower-cli project list -f json | jq -e '.results[] | select(.scm_url | match("http://gitea:3000/student/ansible-sign-demo.git";"i"))'; then
    fail-message "Signed Project's git url is not correct."
fi
