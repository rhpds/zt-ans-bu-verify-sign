#!/bin/bash
echo "Starting module called module-06" >> /tmp/progress.log

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"

# --- Wait for PAH gateway to be ready ---

echo "Waiting for PAH API to become available..." >> /tmp/progress.log
for i in $(seq 1 30); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/v3/namespaces/)
  if [ "$HTTP_CODE" = "200" ]; then
    echo "PAH API ready after ${i} attempts" >> /tmp/progress.log
    break
  fi
  echo "Attempt $i: PAH returned HTTP $HTTP_CODE, retrying in 10s..." >> /tmp/progress.log
  sleep 10
done

# --- Check if signing service already exists, configure if not ---

SIGNING_SVC=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/ | jq -r '.results[0].name // empty')

CONTAINER_GNUPGHOME="/var/lib/pulp/.gnupg"

if [ -z "$SIGNING_SVC" ]; then
  echo "No signing service found, configuring one inside hub containers..." >> /tmp/progress.log

  # GPG batch config — 2048-bit RSA (no subkey) to avoid entropy starvation in containers
  cat > /tmp/pah_gpg.txt <<'GPGEOF'
%echo Generating PAH Signing Service key
Key-Type: RSA
Key-Length: 2048
Name-Real: PAH Signing Service
Name-Comment: collection signing
Name-Email: pah-signing@localhost
Expire-Date: 0
%no-protection
%commit
%echo done
GPGEOF

  # Generate GPG key inside hub worker container using a shared GNUPGHOME
  # on the /var/lib/pulp volume so all workers can access it
  su - rhel -c "podman cp /tmp/pah_gpg.txt automation-hub-worker-1:/tmp/pah_gpg.txt"
  su - rhel -c "podman exec automation-hub-worker-1 bash -c 'mkdir -p ${CONTAINER_GNUPGHOME} && chmod 700 ${CONTAINER_GNUPGHOME} && GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --no-tty --batch --gen-key /tmp/pah_gpg.txt'"

  KEY_FP=$(su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --no-tty --list-keys --with-colons \"PAH Signing Service\"'" | awk -F: '/^fpr:/{print $10; exit}')
  echo "GPG key fingerprint: ${KEY_FP}" >> /tmp/progress.log
  if [ -z "$KEY_FP" ]; then
    echo "ERROR: GPG key generation failed — empty fingerprint" >> /tmp/progress.log
    su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --no-tty --list-keys'" >> /tmp/progress.log 2>&1
  fi

  # Replicate GPG key to worker-2 in case /var/lib/pulp is not a shared volume
  su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --no-tty --batch --yes --armor --export-secret-keys \"PAH Signing Service\"'" > /tmp/pah_signing_private.key
  su - rhel -c "podman exec automation-hub-worker-2 bash -c 'mkdir -p ${CONTAINER_GNUPGHOME} && chmod 700 ${CONTAINER_GNUPGHOME}'"
  su - rhel -c "podman cp /tmp/pah_signing_private.key automation-hub-worker-2:/tmp/pah_signing_private.key"
  su - rhel -c "podman exec automation-hub-worker-2 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --no-tty --batch --yes --import /tmp/pah_signing_private.key && rm -f /tmp/pah_signing_private.key'"
  rm -f /tmp/pah_signing_private.key

  # Create the signing script with explicit GNUPGHOME so the worker
  # process finds the key regardless of which user it runs as
  cat > /tmp/collection_sign.sh <<'SIGNEOF'
#!/usr/bin/env bash
export GNUPGHOME=/var/lib/pulp/.gnupg
FILE_PATH=$1
SIGNATURE_PATH="${FILE_PATH}.asc"
ADMIN_ID="${PULP_SIGNING_KEY_FINGERPRINT}"
gpg --batch --yes --armor --detach-sign --default-key "${ADMIN_ID}" --output "${SIGNATURE_PATH}" "${FILE_PATH}"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  echo "{\"file\": \"${FILE_PATH}\", \"signature\": \"${SIGNATURE_PATH}\"}"
else
  exit $STATUS
fi
SIGNEOF
  chmod +x /tmp/collection_sign.sh

  # Install script into both workers (defensive — in case /var/lib/pulp is not shared)
  for WORKER in automation-hub-worker-1 automation-hub-worker-2; do
    su - rhel -c "podman exec ${WORKER} mkdir -p /var/lib/pulp/scripts"
    su - rhel -c "podman cp /tmp/collection_sign.sh ${WORKER}:/var/lib/pulp/scripts/collection_sign.sh"
    su - rhel -c "podman exec ${WORKER} chmod +x /var/lib/pulp/scripts/collection_sign.sh"
  done

  # Register via pulpcore-manager (validates script + key, more reliable than REST API)
  echo "Registering signing service with pulpcore-manager..." >> /tmp/progress.log
  REGISTER_OUTPUT=$(su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} pulpcore-manager add-signing-service ansible-default /var/lib/pulp/scripts/collection_sign.sh ${KEY_FP}'" 2>&1)
  REGISTER_EXIT=$?
  echo "  pulpcore-manager exit code: ${REGISTER_EXIT}" >> /tmp/progress.log
  echo "  pulpcore-manager output: ${REGISTER_OUTPUT}" >> /tmp/progress.log

  # Verify registration via API
  VERIFY_SS=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/?name=ansible-default | jq -r '.results[0].name // empty')
  echo "  signing service API check: ${VERIFY_SS}" >> /tmp/progress.log
  if [ -z "$VERIFY_SS" ]; then
    echo "ERROR: Signing service not found after registration" >> /tmp/progress.log
  fi
else
  echo "Signing service '${SIGNING_SVC}' already exists" >> /tmp/progress.log
fi

# --- Configure Galaxy NG signing settings and reload API ---
# Settings are on the container overlay (not persistent). The entrypoint
# regenerates settings.py on container start, so restarts wipe our changes.
# After appending, we HUP the API container's gunicorn master (PID 1) to
# make it re-read settings.py. Worker containers can't be reloaded (PID 1
# IS the worker), so auto-sign on approval won't work — the module-07
# solve uses an explicit sign API call instead.

cat > /tmp/galaxy_signing_settings.py <<'SETTINGSEOF'
GALAXY_COLLECTION_SIGNING_SERVICE = "ansible-default"
GALAXY_AUTO_SIGN_COLLECTIONS = True
SETTINGSEOF

for CONTAINER in automation-hub-api automation-hub-worker-1 automation-hub-worker-2; do
  if su - rhel -c "podman exec ${CONTAINER} grep -q '^GALAXY_COLLECTION_SIGNING_SERVICE = \"ansible-default\"' /etc/pulp/settings.py 2>/dev/null"; then
    continue
  fi
  su - rhel -c "podman cp /tmp/galaxy_signing_settings.py ${CONTAINER}:/tmp/galaxy_signing_settings.py"
  su - rhel -c "podman exec -u 0 ${CONTAINER} bash -c 'cat /tmp/galaxy_signing_settings.py >> /etc/pulp/settings.py'"
done
rm -f /tmp/galaxy_signing_settings.py

echo "Galaxy NG signing settings applied" >> /tmp/progress.log

# HUP the API container's gunicorn master to reload settings.py.
# This makes the _ui/v1/settings/ endpoint return the signing service
# config, which tells the hub frontend to show signing badges.
su - rhel -c "podman exec automation-hub-api kill -HUP 1"
sleep 5

SIGNING_SETTING=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/_ui/v1/settings/ | jq -r '.GALAXY_COLLECTION_SIGNING_SERVICE // empty')
echo "  GALAXY_COLLECTION_SIGNING_SERVICE=${SIGNING_SETTING}" >> /tmp/progress.log
if [ "$SIGNING_SETTING" != "ansible-default" ]; then
  echo "  WARNING: Signing settings not loaded by API — hub UI won't show signing badges" >> /tmp/progress.log
fi

# --- Bulk-sign synced repos so pre-populated collections don't show "unsigned" ---

SS_HREF=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/?name=ansible-default \
  | jq -r '.results[0].pulp_href // empty')

if [ -n "$SS_HREF" ]; then
  echo "Bulk-signing synced repos..." >> /tmp/progress.log
  for REPO_NAME in rh-certified validated; do
    REPO_HREF=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
      "${PAH_URL}/api/galaxy/pulp/api/v3/repositories/ansible/ansible/?name=${REPO_NAME}" \
      | jq -r '.results[0].pulp_href // empty')
    if [ -z "$REPO_HREF" ]; then
      echo "  ${REPO_NAME}: repo not found, skipping" >> /tmp/progress.log
      continue
    fi
    SIGN_RESPONSE=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
      -H "Content-Type: application/json" \
      -X POST "${PAH_URL}${REPO_HREF}sign/" \
      -d "{\"signing_service\": \"${SS_HREF}\", \"content_units\": [\"*\"]}")
    SIGN_TASK=$(echo "$SIGN_RESPONSE" | jq -r '.task // empty')
    if [ -n "$SIGN_TASK" ] && [ "$SIGN_TASK" != "null" ]; then
      echo "  ${REPO_NAME}: sign task started (${SIGN_TASK})" >> /tmp/progress.log
      for i in $(seq 1 60); do
        STATE=$(curl -sk -u ${PAH_USER}:${PAH_PASS} "${PAH_URL}${SIGN_TASK}" | jq -r '.state // empty')
        if [ "$STATE" = "completed" ]; then
          echo "  ${REPO_NAME}: signed successfully" >> /tmp/progress.log
          break
        elif [ "$STATE" = "failed" ]; then
          echo "  ${REPO_NAME}: sign task FAILED" >> /tmp/progress.log
          break
        fi
        sleep 2
      done
    else
      echo "  ${REPO_NAME}: no sign task returned — $(echo "$SIGN_RESPONSE" | jq -c '.')" >> /tmp/progress.log
    fi
  done
  echo "Bulk-sign complete" >> /tmp/progress.log
fi

# --- Export the signing service public key ---

EXPORT_FP=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/?name=ansible-default \
  | jq -r '.results[0].pubkey_fingerprint // empty')

if [ -n "$EXPORT_FP" ]; then
  su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --armor --export \"${EXPORT_FP}\"'" > /home/rhel/galaxy_signing_service.asc
fi

if [ ! -s /home/rhel/galaxy_signing_service.asc ]; then
  su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --armor --export \"PAH Signing Service\"'" > /home/rhel/galaxy_signing_service.asc
fi

if [ ! -s /home/rhel/galaxy_signing_service.asc ]; then
  echo "ERROR: Failed to export signing service public key" >> /tmp/progress.log
fi

# --- Create namespaces ---

curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST ${PAH_URL}/api/galaxy/v3/namespaces/ \
  -d '{"name":"ansible","groups":[]}'

curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST ${PAH_URL}/api/galaxy/v3/namespaces/ \
  -d '{"name":"community","groups":[]}'

echo "Namespaces created" >> /tmp/progress.log

# --- Generate API token ---

TOKEN=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -X POST ${PAH_URL}/api/galaxy/v3/auth/token/ | jq -r '.token // empty')

if [ -z "$TOKEN" ]; then
  TOKEN=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/v3/auth/token/ | jq -r '.token // empty')
fi

echo "API token generated" >> /tmp/progress.log

# --- Write ansible.cfg ---

cat > /home/rhel/ansible.cfg <<CFGEOF
[galaxy]
server_list = automation_hub, published_repo

[galaxy_server.automation_hub]
url=${PAH_URL}/api/galaxy/
token=${TOKEN}
validate_certs=false

[galaxy_server.published_repo]
url=${PAH_URL}/api/galaxy/content/published/
token=${TOKEN}
validate_certs=false
CFGEOF

# --- Build test collections ---

COLLECTIONS_DIR=$(mktemp -d)

ansible-galaxy collection init ansible.test_collection --init-path ${COLLECTIONS_DIR}
cat > ${COLLECTIONS_DIR}/ansible/test_collection/galaxy.yml <<GALEOF
namespace: ansible
name: test_collection
version: 1.0.0
readme: README.md
authors:
  - Lab Student <student@localhost>
description: A test collection for signing demonstration
license:
  - GPL-3.0-or-later
repository: https://git.example.com/ansible/test_collection
tags:
  - tools
GALEOF
echo "Initial release" > ${COLLECTIONS_DIR}/ansible/test_collection/CHANGELOG.md
mkdir -p ${COLLECTIONS_DIR}/ansible/test_collection/meta
cat > ${COLLECTIONS_DIR}/ansible/test_collection/meta/runtime.yml <<RTEOF
---
requires_ansible: ">=2.15.0"
RTEOF

mkdir -p ${COLLECTIONS_DIR}/ansible/test_collection/plugins/modules
cat > ${COLLECTIONS_DIR}/ansible/test_collection/plugins/modules/hello_world.py <<'MODEOF'
#!/usr/bin/python
from ansible.module_utils.basic import AnsibleModule

DOCUMENTATION = r'''
module: hello_world
short_description: A simple hello world module
description: Returns a greeting message to demonstrate signed collection usage.
options:
  name:
    description: Name to greet
    type: str
    default: World
author: Lab Student
'''

EXAMPLES = r'''
- name: Say hello
  ansible.test_collection.hello_world:
    name: "Ansible"
'''

RETURN = r'''
msg:
  description: The greeting message
  type: str
  returned: always
'''

def main():
    module = AnsibleModule(argument_spec=dict(name=dict(type='str', default='World')))
    name = module.params['name']
    module.exit_json(changed=False, msg="Hello, {0}! This module is from the signed ansible.test_collection.".format(name))

if __name__ == '__main__':
    main()
MODEOF

ansible-galaxy collection init community.lab_collection --init-path ${COLLECTIONS_DIR}
cat > ${COLLECTIONS_DIR}/community/lab_collection/galaxy.yml <<GALEOF
namespace: community
name: lab_collection
version: 1.0.0
readme: README.md
authors:
  - Lab Student <student@localhost>
description: A lab collection for signing demonstration
license:
  - GPL-3.0-or-later
repository: https://git.example.com/community/lab_collection
tags:
  - tools
GALEOF
echo "Initial release" > ${COLLECTIONS_DIR}/community/lab_collection/CHANGELOG.md
mkdir -p ${COLLECTIONS_DIR}/community/lab_collection/meta
cat > ${COLLECTIONS_DIR}/community/lab_collection/meta/runtime.yml <<RTEOF
---
requires_ansible: ">=2.15.0"
RTEOF

ansible-galaxy collection build ${COLLECTIONS_DIR}/ansible/test_collection --output-path /home/rhel/
ansible-galaxy collection build ${COLLECTIONS_DIR}/community/lab_collection --output-path /home/rhel/

rm -rf ${COLLECTIONS_DIR}

echo "Test collections built" >> /tmp/progress.log

# --- Fix ownership ---

chown rhel:rhel /home/rhel/ansible-test_collection-1.0.0.tar.gz
chown rhel:rhel /home/rhel/community-lab_collection-1.0.0.tar.gz
chown rhel:rhel /home/rhel/ansible.cfg
chown rhel:rhel /home/rhel/galaxy_signing_service.asc 2>/dev/null

echo "Module 06 setup complete" >> /tmp/progress.log
