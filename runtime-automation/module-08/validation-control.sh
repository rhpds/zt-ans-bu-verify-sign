#!/bin/sh
echo "Validated module called module-08" >> /tmp/progress.log

if [[ ! -f "/home/rhel/keyring.kbx" ]]; then
    fail-message "GPG keyring was not created. Import the hub's public key with: gpg --import --no-default-keyring --keyring ~/keyring.kbx ~/galaxy_signing_service.asc"
fi

if [[ ! -d "/home/rhel/.ansible/collections/ansible_collections/community/lab_collection" ]]; then
    fail-message "community.lab_collection was not installed. Run: ansible-galaxy collection install community.lab_collection --keyring ~/keyring.kbx -c"
fi

if [[ ! -f "/home/rhel/.ansible/collections/ansible_collections/community/lab_collection/docs/README.md" ]]; then
    fail-message "You did not create the expected file for the tampering demonstration."
fi
