#!/bin/bash

SETUP_LOG="/home/rhel/setup-provision.log"
echo "=== Setup started: $(date) ===" > $SETUP_LOG

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# # Install collection(s)
# ansible-galaxy collection install ansible.eda
# ansible-galaxy collection install community.general
# ansible-galaxy collection install ansible.windows
# ansible-galaxy collection install microsoft.ad

echo "[1/6] Making ansible-sign available..." >> $SETUP_LOG
# Bootstrap pip using Python's built-in ensurepip (no dnf repos needed),
# then install ansible-sign from PyPI.
python3 -m ensurepip --upgrade >> $SETUP_LOG 2>&1
echo "  ensurepip exit code: $?" >> $SETUP_LOG
python3 -m pip install ansible-sign >> $SETUP_LOG 2>&1
echo "  pip install ansible-sign exit code: $?" >> $SETUP_LOG

# Verify it works as rhel user
RHEL_CHECK=$(su - rhel -c "ansible-sign --version 2>&1")
echo "  rhel user ansible-sign: $RHEL_CHECK" >> $SETUP_LOG

echo "[3/6] Setting up rhel user sudo and SSH..." >> $SETUP_LOG
# # ## setup rhel user
touch /etc/sudoers.d/rhel_sudoers
echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
cp -a /root/.ssh/* /home/$USER/.ssh/.
chown -R rhel:rhel /home/$USER/.ssh
echo "  sudoers and SSH: done" >> $SETUP_LOG

echo "[4/6] Configuring git credentials..." >> $SETUP_LOG
su - rhel -c "git config --global credential.helper store"
touch /home/rhel/.git-credentials
chown rhel:rhel /home/rhel/.git-credentials
su - rhel -c "echo 'http://gitea:gitea@gitea:3000' >> /home/rhel/.git-credentials"
su - rhel -c "git config --global user.name gitea"
su - rhel -c "git config --global user.email student@localhost"
echo "  git credentials: done" >> $SETUP_LOG

echo "[5/6] Creating ansible-sign-demo directory..." >> $SETUP_LOG
sudo mkdir -p /home/rhel/ansible-sign-demo
sudo chown rhel:rhel /home/rhel/ansible-sign-demo
echo "  ansible-sign-demo: done" >> $SETUP_LOG

echo "[6/6] Final checks..." >> $SETUP_LOG
echo "  ansible-sign (rhel): $(su - rhel -c 'which ansible-sign 2>&1')" >> $SETUP_LOG
echo "  version (rhel): $(su - rhel -c 'ansible-sign --version 2>&1')" >> $SETUP_LOG
echo "  python3: $(python3 --version 2>&1)" >> $SETUP_LOG

chown rhel:rhel $SETUP_LOG
echo "=== Setup finished: $(date) ===" >> $SETUP_LOG
