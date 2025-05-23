#!/bin/sh

# Set fail-fast behavior for the entire script.
set -e

# This script should be run manually before executing `docker compose up`.
# It creates the required secret files based on the environment variables.
#
# Usage example:
#   export JENKINS_ADMIN_PASSWORD=Admin@123
#   export JENKINS_CI_USER_PASSWORD=cI_User@123
#   ./scripts/bootstrap.sh

# Capture env vars immediately and unset right away — upfront and first thing,
# so even if the below script fails for whatever reason, the sensitive vars are always unset.
JENKINS_ADMIN_PASSWORD_VALUE="$JENKINS_ADMIN_PASSWORD"
unset JENKINS_ADMIN_PASSWORD

JENKINS_CI_USER_PASSWORD_VALUE="$JENKINS_CI_USER_PASSWORD"
unset JENKINS_CI_USER_PASSWORD

SECRET_DIR="./secrets/jcasc_secrets"

mkdir -p "$SECRET_DIR"
chmod 0700 "$SECRET_DIR"

write_secret() {
  USER_PASSWORD="$1"
  FILE_PATH="$SECRET_DIR/$2"

  if [ -n "$USER_PASSWORD" ]; then
    printf %s "$USER_PASSWORD" | base64 | tr -d '\n' > "$FILE_PATH"
    chmod 0600 "$FILE_PATH"
    echo "[INFO] Secret has been written to $FILE_PATH"
  else
    echo "[WARN] Password is empty. $FILE_PATH not created." >&2
  fi
}

write_secret "$JENKINS_ADMIN_PASSWORD_VALUE" "admin_password"
write_secret "$JENKINS_CI_USER_PASSWORD_VALUE" "ci_user_password"

echo "[DONE] Secrets written. Now run: docker compose up"
