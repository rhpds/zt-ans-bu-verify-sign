#!/bin/bash
LOG="/tmp/solve-module-08.log"
echo "=== Module 08 solve started: $(date) ===" > $LOG

# --- Step 1: Import the hub's public key into a keyring ---
echo "[1/5] Importing hub public key into keyring..." >> $LOG
su - rhel -c "gpg --import --no-default-keyring --keyring ~/keyring.kbx ~/galaxy_signing_service.asc" >> $LOG 2>&1
echo "  exit code: $?" >> $LOG

KEY_FP=$(su - rhel -c "gpg --no-default-keyring --keyring ~/keyring.kbx --with-colons --list-keys 2>/dev/null" | awk -F: '/^fpr:/{print $10; exit}')
if [ -n "$KEY_FP" ]; then
  su - rhel -c "echo '${KEY_FP}:6:' | gpg --no-default-keyring --keyring ~/keyring.kbx --import-ownertrust" >> $LOG 2>&1
  echo "  trust set for ${KEY_FP}" >> $LOG
fi

# Import keys from default keyring so GPG trustdb stays consistent (prevents exit code 2)
su - rhel -c "gpg --export --armor 2>/dev/null | gpg --no-default-keyring --keyring ~/keyring.kbx --import 2>/dev/null" >> $LOG 2>&1 || true

# --- Step 2: Install collection without verification ---
echo "[2/5] Installing ansible.test_collection (no verification)..." >> $LOG
su - rhel -c "cd ~ && ansible-galaxy collection install ansible.test_collection -c" >> $LOG 2>&1
echo "  exit code: $?" >> $LOG

# --- Step 3: Install collection with verification ---
echo "[3/5] Installing community.lab_collection (with keyring verification)..." >> $LOG
su - rhel -c "cd ~ && ansible-galaxy collection install community.lab_collection --keyring ~/keyring.kbx -c -vvvv" >> $LOG 2>&1
echo "  exit code: $?" >> $LOG

# --- Step 4: Tamper with the collection ---
echo "[4/5] Tampering with installed collection..." >> $LOG
su - rhel -c "touch ~/.ansible/collections/ansible_collections/community/lab_collection/docs/README.md" >> $LOG 2>&1
echo "  exit code: $?" >> $LOG

# --- Step 5: Verify (shows tampering) ---
echo "[5/5] Verifying collection integrity (should report tampering)..." >> $LOG
su - rhel -c "cd ~ && ansible-galaxy collection verify community.lab_collection --keyring ~/keyring.kbx -c --server published_repo" >> $LOG 2>&1 || true
echo "  exit code: $?" >> $LOG

echo "=== Module 08 solve finished: $(date) ===" >> $LOG
