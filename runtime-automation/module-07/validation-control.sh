#!/bin/sh
echo "Validated module called module-07" >> /tmp/progress.log

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"

ANSIBLE_SIGNED=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/_ui/v1/repo/published/ansible/test_collection/ | jq -r '.latest_version.sign_state')

COMMUNITY_SIGNED=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/_ui/v1/repo/published/community/lab_collection/ | jq -r '.latest_version.sign_state')

if [ "$ANSIBLE_SIGNED" != "signed" ]; then
    fail-message "ansible.test_collection has not been signed and approved"
fi

if [ "$COMMUNITY_SIGNED" != "signed" ]; then
    fail-message "community.lab_collection has not been signed and approved"
fi
