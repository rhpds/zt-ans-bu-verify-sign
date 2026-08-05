#!/bin/bash
echo "Starting module called module-09" >> /tmp/progress.log

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"

# --- Ensure hub API has signing settings loaded (survives container restarts) ---
SIGNING_SETTING=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/_ui/v1/settings/ | jq -r '.GALAXY_COLLECTION_SIGNING_SERVICE // empty')
if [ "$SIGNING_SETTING" != "ansible-default" ]; then
  echo "Re-applying signing settings to hub API..." >> /tmp/progress.log
  cat > /tmp/galaxy_signing_settings.py <<'SETTINGSEOF'
GALAXY_COLLECTION_SIGNING_SERVICE = "ansible-default"
GALAXY_AUTO_SIGN_COLLECTIONS = True
SETTINGSEOF
  for CONTAINER in automation-hub-api automation-hub-worker-1 automation-hub-worker-2; do
    if ! su - rhel -c "podman exec ${CONTAINER} grep -q '^GALAXY_COLLECTION_SIGNING_SERVICE = \"ansible-default\"' /etc/pulp/settings.py 2>/dev/null"; then
      su - rhel -c "podman cp /tmp/galaxy_signing_settings.py ${CONTAINER}:/tmp/galaxy_signing_settings.py"
      su - rhel -c "podman exec -u 0 ${CONTAINER} bash -c 'cat /tmp/galaxy_signing_settings.py >> /etc/pulp/settings.py'"
    fi
  done
  rm -f /tmp/galaxy_signing_settings.py
  su - rhel -c "podman exec automation-hub-api kill -HUP 1"
  sleep 5
  echo "  signing settings re-applied" >> /tmp/progress.log
fi

# --- Ensure public key file exists (re-export if missing/empty) ---
if [ ! -s /home/rhel/galaxy_signing_service.asc ]; then
  echo "Re-exporting signing service public key..." >> /tmp/progress.log
  CONTAINER_GNUPGHOME="/var/lib/pulp/.gnupg"
  EXPORT_FP=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/?name=ansible-default \
    | jq -r '.results[0].pubkey_fingerprint // empty')
  if [ -n "$EXPORT_FP" ]; then
    su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --armor --export \"${EXPORT_FP}\"'" > /home/rhel/galaxy_signing_service.asc
    chown rhel:rhel /home/rhel/galaxy_signing_service.asc
    echo "  public key re-exported (fingerprint: ${EXPORT_FP})" >> /tmp/progress.log
  fi
fi

# --- Verify ansible.test_collection is published and signed ---
SIGN_STATE=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/_ui/v1/repo/published/ansible/test_collection/ \
  | jq -r '.latest_version.sign_state // empty')
if [ "$SIGN_STATE" != "signed" ]; then
  echo "WARNING: ansible.test_collection sign_state is '${SIGN_STATE}' (expected 'signed')" >> /tmp/progress.log
  echo "  Module 07 may not have been completed — collections must be approved and signed" >> /tmp/progress.log
fi

# --- Create the playbook that uses the signed collection ---
cat > /home/rhel/ansible-sign-demo/playbooks/use_signed_collection.yml <<'PBEOF'
---
- name: Use a module from a signed collection
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Call hello_world from ansible.test_collection
      ansible.test_collection.hello_world:
        name: "AAP Controller"
      register: result

    - name: Show the result
      ansible.builtin.debug:
        var: result.msg
PBEOF

# --- Install signed collection directly into the project ---
su - rhel -c "cd ~ && ansible-galaxy collection install ansible.test_collection -c -p ~/ansible-sign-demo/playbooks/collections/" >> /tmp/progress.log 2>&1
echo "  collection install exit code: $?" >> /tmp/progress.log

# --- Update MANIFEST.in to include collections directory ---
if ! grep -q 'recursive-include playbooks/collections' /home/rhel/ansible-sign-demo/MANIFEST.in 2>/dev/null; then
  echo "recursive-include playbooks/collections *" >> /home/rhel/ansible-sign-demo/MANIFEST.in
fi

# --- Fix ownership before signing ---
chown -R rhel:rhel /home/rhel/ansible-sign-demo/

# --- Re-sign the project ---
echo "Re-signing project with ansible-sign..." >> /tmp/progress.log
su - rhel -c "/usr/local/bin/ansible-sign project gpg-sign ~/ansible-sign-demo" >> /tmp/progress.log 2>&1
SIGN_EXIT=$?
echo "  ansible-sign exit code: ${SIGN_EXIT}" >> /tmp/progress.log

# --- Git add, commit, and push ---
echo "Pushing updated project to Gitea..." >> /tmp/progress.log
su - rhel -c 'cd ~/ansible-sign-demo && GIT_TERMINAL_PROMPT=0 git add -A && git commit -m "Add playbook using signed collection and requirements.yml" && GIT_TERMINAL_PROMPT=0 git push' >> /tmp/progress.log 2>&1
PUSH_EXIT=$?
echo "  git push exit code: ${PUSH_EXIT}" >> /tmp/progress.log

echo "Module 09 setup complete" >> /tmp/progress.log
