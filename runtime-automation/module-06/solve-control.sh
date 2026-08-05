#!/bin/bash
LOG="/tmp/solve-module-06.log"
echo "=== Module 06 solve started: $(date) ===" > $LOG

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"

# --- Wait for PAH API to be ready ---
echo "[1/3] Waiting for PAH API..." >> $LOG
for i in $(seq 1 30); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/v3/namespaces/)
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  PAH API ready after ${i} attempts" >> $LOG
    break
  fi
  echo "  Attempt $i: HTTP $HTTP_CODE, retrying in 5s..." >> $LOG
  sleep 5
done

# --- Read API token from ansible.cfg written by setup ---
echo "[2/3] Reading API token from ansible.cfg..." >> $LOG
TOKEN=$(grep '^token=' /home/rhel/ansible.cfg | head -1 | cut -d= -f2)
if [ -z "$TOKEN" ]; then
  echo "  No token in ansible.cfg, generating new one..." >> $LOG
  TOKEN=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    -X POST ${PAH_URL}/api/galaxy/v3/auth/token/ | jq -r '.token // empty')
  if [ -z "$TOKEN" ]; then
    TOKEN=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
      ${PAH_URL}/api/galaxy/v3/auth/token/ | jq -r '.token // empty')
  fi
fi
echo "  token: ${TOKEN:0:8}..." >> $LOG

# --- Publish collections ---
echo "[3/3] Publishing collections to PAH..." >> $LOG

echo "  Publishing ansible.test_collection..." >> $LOG
su - rhel -c "ansible-galaxy collection publish /home/rhel/ansible-test_collection-1.0.0.tar.gz --server ${PAH_URL}/api/galaxy/ --token ${TOKEN} -c" >> $LOG 2>&1
echo "  exit code: $?" >> $LOG

echo "  Publishing community.lab_collection..." >> $LOG
su - rhel -c "ansible-galaxy collection publish /home/rhel/community-lab_collection-1.0.0.tar.gz --server ${PAH_URL}/api/galaxy/ --token ${TOKEN} -c" >> $LOG 2>&1
echo "  exit code: $?" >> $LOG

echo "=== Module 06 solve finished: $(date) ===" >> $LOG
