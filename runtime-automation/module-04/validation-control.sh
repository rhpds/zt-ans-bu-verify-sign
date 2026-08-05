#!/bin/bash

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"
$RUNAS bash<<_


if [[ ! -f "/home/rhel/ansible-sign-demo/playbooks/hello_world.yml" ]]; then
    fail-message "Required playbook was not created in the local project."
elif [[ ! -f "/home/rhel/ansible-sign-demo/inventory" ]]; then
    fail-message "Inventory file was not created in the local project"
elif cat /home/rhel/ansible-sign-demo/.ansible-sign/sha256sum.txt | grep -q 'inventory'; then
    fail-message "Signing is not needed in this challenge"
fi
