#!/bin/sh
echo "Validated module called module-05" >> /tmp/progress.log

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"
$RUNAS bash<<_


if ! cat /home/rhel/ansible-sign-demo/.ansible-sign/sha256sum.txt | grep -q 'inventory'; then
    fail-message "Signatures for new files were not added"
elif ! cat /home/rhel/ansible-sign-demo/.ansible-sign/sha256sum.txt | grep -q 'playbooks/hello_world.yml'; then
    fail-message "Signatures for new files were not added"
fi
