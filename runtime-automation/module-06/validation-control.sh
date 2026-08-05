#!/bin/sh
LOG="/tmp/validation-module-06.log"
echo "=== Module 06 validation started: $(date) ===" > $LOG

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"
CURL_OPTS="-sk --connect-timeout 10 --max-time 30"

echo "[1] Checking staging repo for ansible.test_collection..." >> $LOG
ANSIBLE_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
  "${PAH_URL}/api/galaxy/_ui/v1/repo/staging/ansible/test_collection/")
ANSIBLE_CODE=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -u ${PAH_USER}:${PAH_PASS} \
  "${PAH_URL}/api/galaxy/_ui/v1/repo/staging/ansible/test_collection/")
echo "  HTTP ${ANSIBLE_CODE}" >> $LOG
echo "  response: ${ANSIBLE_RESPONSE}" >> $LOG

echo "[2] Checking staging repo for community.lab_collection..." >> $LOG
COMMUNITY_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
  "${PAH_URL}/api/galaxy/_ui/v1/repo/staging/community/lab_collection/")
COMMUNITY_CODE=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -u ${PAH_USER}:${PAH_PASS} \
  "${PAH_URL}/api/galaxy/_ui/v1/repo/staging/community/lab_collection/")
echo "  HTTP ${COMMUNITY_CODE}" >> $LOG
echo "  response: ${COMMUNITY_RESPONSE}" >> $LOG

if [ "$ANSIBLE_CODE" != "200" ]; then
    fail-message "ansible.test_collection was not published to Private Automation Hub"
fi

if [ "$COMMUNITY_CODE" != "200" ]; then
    fail-message "community.lab_collection was not published to Private Automation Hub"
fi

echo "=== Module 06 validation passed: $(date) ===" >> $LOG
