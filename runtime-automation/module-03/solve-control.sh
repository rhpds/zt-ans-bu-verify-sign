#!/bin/bash
LOG="/tmp/solve-module-03.log"
echo "=== Module 03 solve started: $(date) ===" > $LOG

AAP_URL="https://localhost"
AAP_USER="admin"
AAP_PASS="ansible123!"
CURL_OPTS="-sk --connect-timeout 10 --max-time 30"

# --- Step 1: Create MANIFEST.in ---
echo "[1/5] Creating MANIFEST.in..." >> $LOG
su - rhel <<'STEP1' >> $LOG 2>&1
cat << EOF > ~/ansible-sign-demo/MANIFEST.in
recursive-exclude .git *
include README.md
EOF
STEP1
echo "  exit code: $?" >> $LOG

# --- Step 2: Sign the project ---
echo "[2/5] Signing project with ansible-sign..." >> $LOG
su - rhel -c "/usr/local/bin/ansible-sign project gpg-sign ~/ansible-sign-demo" >> $LOG 2>&1
echo "  exit code: $?" >> $LOG
echo "  completed: $(date)" >> $LOG

# --- Step 3: Git add, commit, push ---
echo "[3/5] Git commit and push..." >> $LOG
su - rhel <<'STEP3' >> $LOG 2>&1
export GIT_TERMINAL_PROMPT=0
cd ~/ansible-sign-demo
git add .ansible-sign/ MANIFEST.in
git commit -m "Adding signatures for empty project"
git push
STEP3
echo "  exit code: $?" >> $LOG
echo "  completed: $(date)" >> $LOG

# --- Step 4: Look up org ID, then create credential ---
echo "[4/5] Creating GPG credential in AAP..." >> $LOG

echo "  Looking up Default org..." >> $LOG
ORG_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/organizations/?name=Default" \
  | jq -r '.results[0].id')
echo "  org ID: ${ORG_ID}" >> $LOG

GPG_KEY=$(cat /home/rhel/signing_demo.asc)
if [ -z "$GPG_KEY" ]; then
    echo "  ERROR: /home/rhel/signing_demo.asc is empty or missing" >> $LOG
fi

echo "  Looking up GPG Public Key credential type..." >> $LOG
CRED_TYPE_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/credential_types/?name=GPG+Public+Key" \
  | jq -r '.results[0].id')
echo "  credential type ID: ${CRED_TYPE_ID}" >> $LOG

if [ "$CRED_TYPE_ID" = "null" ] || [ -z "$CRED_TYPE_ID" ]; then
    echo "  ERROR: Could not find GPG Public Key credential type" >> $LOG
    echo "=== Module 03 solve FAILED at step 4: $(date) ===" >> $LOG
    exit 1
fi

CRED_PAYLOAD=$(jq -n \
  --arg name "ansible-sign" \
  --argjson cred_type "$CRED_TYPE_ID" \
  --argjson org "$ORG_ID" \
  --arg gpg_key "$GPG_KEY" \
  '{
    name: $name,
    credential_type: $cred_type,
    organization: $org,
    inputs: { gpg_public_key: $gpg_key }
  }')

echo "  POSTing credential..." >> $LOG
CRED_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${AAP_URL}/api/controller/v2/credentials/" \
  -d "$CRED_PAYLOAD")
echo "  credential response: $CRED_RESPONSE" >> $LOG

CRED_ID=$(echo "$CRED_RESPONSE" | jq -r '.id')
echo "  credential ID: ${CRED_ID}" >> $LOG

if [ "$CRED_ID" = "null" ] || [ -z "$CRED_ID" ]; then
    echo "  ERROR: Failed to create credential" >> $LOG
    echo "=== Module 03 solve FAILED at step 4: $(date) ===" >> $LOG
    exit 1
fi

# --- Step 5: Create project with signature validation credential ---
echo "[5/5] Creating project in AAP..." >> $LOG

PROJECT_PAYLOAD=$(jq -n \
  --arg name "Signed Project" \
  --arg scm_url "http://gitea:3000/student/ansible-sign-demo.git" \
  --argjson org_id "$ORG_ID" \
  --argjson cred_id "$CRED_ID" \
  '{
    name: $name,
    scm_type: "git",
    scm_url: $scm_url,
    organization: $org_id,
    signature_validation_credential: $cred_id
  }')

echo "  POSTing project..." >> $LOG
PROJECT_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${AAP_URL}/api/controller/v2/projects/" \
  -d "$PROJECT_PAYLOAD")
echo "  project response: $PROJECT_RESPONSE" >> $LOG

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.id')
echo "  project ID: ${PROJECT_ID}" >> $LOG

echo "=== Module 03 solve finished: $(date) ===" >> $LOG
