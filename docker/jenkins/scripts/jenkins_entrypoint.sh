#!/bin/sh

SECRET_DIR="/var/jenkins_home/secrets"

mkdir -p "$SECRET_DIR"
chmod 0700 "$SECRET_DIR"

write_secret() {
  VAR_NAME="$1"
  FILE_NAME="$2"
  USER_PASSWORD=$(eval "echo \$$VAR_NAME")

  if [ -n "$USER_PASSWORD" ]; then
    printf %s "$USER_PASSWORD" | base64 | tr -d '\n' > "$SECRET_DIR/$FILE_NAME"
    chmod 0600 "$SECRET_DIR/$FILE_NAME"
    echo "[INFO] Secret has been written to $SECRET_DIR/$FILE_NAME"
  else
    echo "[WARN] Environment variable $VAR_NAME is empty. $FILE_NAME not created." >&2
  fi

  unset "$VAR_NAME"
}

write_secret "ADMIN_PASSWORD" "admin_password"
write_secret "CI_USER_PASSWORD" "ci_user_password"

exec /usr/local/bin/jenkins.sh
