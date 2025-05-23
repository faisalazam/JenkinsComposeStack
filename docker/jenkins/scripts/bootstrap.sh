#!/bin/sh

# Capture env vars immediately and unset right away — upfront and first thing,
# so even if the below script fails for whatever reason, the sensitive vars are always unset.
ADMIN_PASSWORD_VALUE="$ADMIN_PASSWORD"
unset ADMIN_PASSWORD

CI_USER_PASSWORD_VALUE="$CI_USER_PASSWORD"
unset CI_USER_PASSWORD

SECRET_DIR="${JENKINS_JCASC_SECRETS_DIR}"

mkdir -p "$SECRET_DIR"
chmod 0700 "$SECRET_DIR"

write_secret() {
  USER_PASSWORD="$1"
  FILE_NAME="$2"

  if [ -n "$USER_PASSWORD" ]; then
    printf %s "$USER_PASSWORD" | base64 | tr -d '\n' > "$SECRET_DIR/$FILE_NAME"
    chmod 0600 "$SECRET_DIR/$FILE_NAME"
    echo "[INFO] Secret has been written to $SECRET_DIR/$FILE_NAME"
  else
    echo "[WARN] Password is empty. $FILE_NAME not created." >&2
  fi
}

write_secret "$ADMIN_PASSWORD_VALUE" "admin_password"
write_secret "$CI_USER_PASSWORD_VALUE" "ci_user_password"

exec /usr/local/bin/jenkins.sh
