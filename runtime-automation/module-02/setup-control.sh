#!/bin/sh
echo "Starting module called module-02" >> /tmp/progress.log

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

#Runs bash with commands between '_' as nobody if possible
$RUNAS bash<<_

cat << EOF > /home/rhel/gpg.txt
%echo Generating a basic OpenPGP key
Key-Type: default
Key-Length: 4096
Subkey-Type: default
Subkey-Length: default
Name-Real: Instruqt
Name-Comment: with no passphrase
Name-Email: student@localhost
Expire-Date: 0
%no-ask-passphrase
%no-protection
# Do a commit here, so that we can later print "done" :-)
%commit
%echo done
EOF

rm -rf ~/ansible-test_collection-1.0.0.tar.gz
rm -rf ~/community-lab_collection-1.0.0.tar.gz
rm -rf ~/ansible.cfg
