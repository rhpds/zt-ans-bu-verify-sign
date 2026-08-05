#!/bin/sh
echo "Starting module called module-05" >> /tmp/progress.log

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

#Runs bash with commands between '_' as nobody if possible
$RUNAS bash<<_

rm -rf ~/ansible-test_collection-1.0.0.tar.gz
rm -rf ~/community-lab_collection-1.0.0.tar.gz
rm -rf ~/ansible.cfg
