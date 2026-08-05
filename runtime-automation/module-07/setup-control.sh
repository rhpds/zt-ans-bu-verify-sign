#!/bin/bash
echo "Starting module called module-07" >> /tmp/progress.log

su - rhel -c "rm -rf ~/.ansible/collections/ansible_collections/"

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
