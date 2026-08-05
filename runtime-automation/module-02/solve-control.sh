#!/bin/bash
LOG="/tmp/solve-module-02.log"
echo "=== Module 02 solve started: $(date) ===" > $LOG

echo "[1/2] Generating GPG keypair..." >> $LOG
su - rhel <<'SOLVE' >> $LOG 2>&1
gpg --batch --gen-key ~/gpg.txt
SOLVE
echo "  exit code: $?" >> $LOG
echo "  completed: $(date)" >> $LOG

echo "[2/2] Exporting public key..." >> $LOG
su - rhel <<'SOLVE' >> $LOG 2>&1
gpg --output ~/signing_demo.asc --armor --export
SOLVE
echo "  exit code: $?" >> $LOG

echo "=== Module 02 solve finished: $(date) ===" >> $LOG
