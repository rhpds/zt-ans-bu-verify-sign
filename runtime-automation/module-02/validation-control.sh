#!/bin/sh
echo "Validated module called module-02" >> /tmp/progress.log

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"
$RUNAS bash<<_

gpg --list-keys | grep Instruqt

if [[ $? -ne 0 ]]
then :
    fail-message "Could not find the GPG keypair in the list of keys"
elif [[ ! -f "/home/rhel/signing_demo.asc" ]];
then :
    fail-message "Public key was not exported!"
fi
_
