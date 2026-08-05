#!/bin/sh
echo "Starting module called module-01" >> /tmp/progress.log

su - rhel -c "git clone http://gitea:3000/student/ansible-sign-demo.git"
