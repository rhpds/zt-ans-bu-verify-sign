#!/bin/bash

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

retry() {
    for i in {1..3}; do
        echo "Attempt $i: $2"
        if $1; then
            return 0
        fi
        [ $i -lt 3 ] && sleep 5
    done
    echo "Failed after 3 attempts: $2"
    exit 1
}

retry "curl -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt"
retry "update-ca-trust"
retry "rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm"
retry "subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}"
retry "dnf install python3 python3-pip"


# # Install collection(s)
# ansible-galaxy collection install ansible.eda
# ansible-galaxy collection install community.general
# ansible-galaxy collection install ansible.windows
# ansible-galaxy collection install microsoft.ad

pip3 install ansible-sign
# # ## setup rhel user
touch /etc/sudoers.d/rhel_sudoers
echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
cp -a /root/.ssh/* /home/$USER/.ssh/.
chown -R rhel:rhel /home/$USER/.ssh

git config credential.helper store
touch /home/rhel/.git-credentials
su - rhel -c "echo 'https://gitea:gitea' >> /home/rhel/.git-credentials"
git push -u origin master
su - rhel -c "git config --global user.name gitea"
su - rhel -c "git config --global user.email student@localhost"

sudo mkdir -p /home/rhel/ansible-sign-demo
sudo chown rhel:rhel /home/rhel/ansible-sign-demo
