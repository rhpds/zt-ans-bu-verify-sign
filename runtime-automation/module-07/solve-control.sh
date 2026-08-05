#!/bin/bash
LOG="/tmp/solve-module-07.log"
echo "=== Module 07 solve started: $(date) ===" > $LOG

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"
CURL_OPTS="-sk --connect-timeout 10 --max-time 30"

# Helper: wait for a Pulp task to complete
wait_for_task() {
  local TASK_URL="$1"
  local LABEL="$2"
  if [ -z "$TASK_URL" ] || [ "$TASK_URL" = "null" ]; then
    echo "    no task href for ${LABEL}, assuming synchronous" >> $LOG
    return 0
  fi
  echo "    waiting for ${LABEL} task: ${TASK_URL}" >> $LOG
  for i in $(seq 1 60); do
    TASK_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} "${PAH_URL}${TASK_URL}")
    STATE=$(echo "$TASK_RESPONSE" | jq -r '.state // empty')
    if [ "$STATE" = "completed" ]; then
      echo "    ${LABEL} task completed (attempt $i)" >> $LOG
      return 0
    elif [ "$STATE" = "failed" ]; then
      echo "    ERROR: ${LABEL} task FAILED" >> $LOG
      echo "    task response: $TASK_RESPONSE" >> $LOG
      return 1
    fi
    sleep 2
  done
  echo "    ERROR: ${LABEL} task timed out after 120s" >> $LOG
  return 1
}

# --- Step 1: Verify signing service exists ---
echo "[1/5] Checking signing service..." >> $LOG
SS_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
  "${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/?name=ansible-default")
echo "  response: $SS_RESPONSE" >> $LOG

SS_HREF=$(echo "$SS_RESPONSE" | jq -r '.results[0].pulp_href // empty')
SS_NAME=$(echo "$SS_RESPONSE" | jq -r '.results[0].name // empty')
echo "  signing service: name=${SS_NAME} href=${SS_HREF}" >> $LOG

if [ -z "$SS_HREF" ]; then
  echo "  ERROR: No signing service 'ansible-default' found." >> $LOG
  echo "  Module-06 setup may have failed to register the signing service." >> $LOG
  echo "=== Module 07 solve FAILED: $(date) ===" >> $LOG
  exit 1
fi

# --- Step 2: Move collections from staging to published (wait for each) ---
echo "[2/5] Moving collections from staging to published..." >> $LOG

echo "  Moving ansible.test_collection..." >> $LOG
MOVE1_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${PAH_URL}/api/galaxy/v3/collections/ansible/test_collection/versions/1.0.0/move/staging/published/")
MOVE1_CODE=$?
echo "  response (curl exit $MOVE1_CODE): $MOVE1_RESPONSE" >> $LOG

MOVE1_TASK=$(echo "$MOVE1_RESPONSE" | jq -r '.task // empty')
wait_for_task "$MOVE1_TASK" "move-ansible"

echo "  Moving community.lab_collection..." >> $LOG
MOVE2_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${PAH_URL}/api/galaxy/v3/collections/community/lab_collection/versions/1.0.0/move/staging/published/")
MOVE2_CODE=$?
echo "  response (curl exit $MOVE2_CODE): $MOVE2_RESPONSE" >> $LOG

MOVE2_TASK=$(echo "$MOVE2_RESPONSE" | jq -r '.task // empty')
wait_for_task "$MOVE2_TASK" "move-community"

# --- Step 3: Verify collections are in published repo ---
echo "[3/5] Verifying collections in published repo..." >> $LOG
for COLL in "ansible/test_collection" "community/lab_collection"; do
  PUB_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
    "${PAH_URL}/api/galaxy/_ui/v1/repo/published/${COLL}/")
  PUB_CODE=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -u ${PAH_USER}:${PAH_PASS} \
    "${PAH_URL}/api/galaxy/_ui/v1/repo/published/${COLL}/")
  CURRENT_SIGN=$(echo "$PUB_RESPONSE" | jq -r '.latest_version.sign_state // empty')
  echo "  ${COLL}: HTTP ${PUB_CODE}, sign_state=${CURRENT_SIGN}" >> $LOG
done

# --- Step 4: Sign all content in published repo via Pulp API ---
echo "[4/5] Signing published repository content..." >> $LOG

REPO_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
  "${PAH_URL}/api/galaxy/pulp/api/v3/repositories/ansible/ansible/?name=published")
echo "  repo query response: $REPO_RESPONSE" >> $LOG

REPO_HREF=$(echo "$REPO_RESPONSE" | jq -r '.results[0].pulp_href // empty')
echo "  repo href: $REPO_HREF" >> $LOG

if [ -z "$REPO_HREF" ]; then
  echo "  ERROR: Could not find 'published' repository" >> $LOG
  echo "=== Module 07 solve FAILED: $(date) ===" >> $LOG
  exit 1
fi

SIGN_PAYLOAD="{\"signing_service\": \"${SS_HREF}\", \"content_units\": [\"*\"]}"
echo "  sign payload: $SIGN_PAYLOAD" >> $LOG
echo "  sign URL: ${PAH_URL}${REPO_HREF}sign/" >> $LOG

SIGN_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${PAH_URL}${REPO_HREF}sign/" \
  -d "$SIGN_PAYLOAD")
echo "  sign response: $SIGN_RESPONSE" >> $LOG

SIGN_TASK=$(echo "$SIGN_RESPONSE" | jq -r '.task // empty')
wait_for_task "$SIGN_TASK" "sign"
SIGN_RESULT=$?

if [ $SIGN_RESULT -ne 0 ]; then
  echo "  Sign task did not complete successfully, checking task error..." >> $LOG
  if [ -n "$SIGN_TASK" ] && [ "$SIGN_TASK" != "null" ]; then
    TASK_DETAIL=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} "${PAH_URL}${SIGN_TASK}")
    TASK_ERROR=$(echo "$TASK_DETAIL" | jq -r '.error // empty')
    echo "  task error: $TASK_ERROR" >> $LOG
  fi
fi

# --- Step 5: Verify sign_state ---
echo "[5/5] Verifying final sign_state..." >> $LOG
ALL_SIGNED=true
for COLL in "ansible/test_collection" "community/lab_collection"; do
  FINAL_RESPONSE=$(curl $CURL_OPTS -u ${PAH_USER}:${PAH_PASS} \
    "${PAH_URL}/api/galaxy/_ui/v1/repo/published/${COLL}/")
  SIGN_STATE=$(echo "$FINAL_RESPONSE" | jq -r '.latest_version.sign_state // empty')
  echo "  ${COLL}: sign_state=${SIGN_STATE}" >> $LOG
  if [ "$SIGN_STATE" != "signed" ]; then
    ALL_SIGNED=false
    echo "  WARNING: ${COLL} is NOT signed (sign_state=${SIGN_STATE})" >> $LOG
  fi
done

if [ "$ALL_SIGNED" = true ]; then
  echo "  All collections signed successfully" >> $LOG
else
  echo "  WARNING: Not all collections are signed. Check log above for errors." >> $LOG
fi

echo "=== Module 07 solve finished: $(date) ===" >> $LOG
