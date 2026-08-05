#!/bin/bash
echo "Starting module called module-08" >> /tmp/progress.log

su - rhel <<'_'
rm -rf ~/.ansible/collections/ansible_collections/
rm -f ~/keyring.kbx ~/keyring.kbx~
_

# --- Ensure hub API has signing settings loaded (survives container restarts) ---
SIGNING_SETTING=$(curl -sk -u admin:ansible123! \
  https://localhost/api/galaxy/_ui/v1/settings/ | jq -r '.GALAXY_COLLECTION_SIGNING_SERVICE // empty')
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
  EXPORT_FP=$(curl -sk -u admin:ansible123! \
    https://localhost/api/galaxy/pulp/api/v3/signing-services/?name=ansible-default \
    | jq -r '.results[0].pubkey_fingerprint // empty')
  if [ -n "$EXPORT_FP" ]; then
    su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --armor --export \"${EXPORT_FP}\"'" > /home/rhel/galaxy_signing_service.asc
    chown rhel:rhel /home/rhel/galaxy_signing_service.asc
    echo "  public key re-exported (fingerprint: ${EXPORT_FP})" >> /tmp/progress.log
  fi
fi
