#!/bin/sh

# This is a helper script to create Jenkins credentials via the API.
#
# While credentials can also be created using Jenkins Configuration as Code (JCasC) YAML files,
# that method has a drawback: secrets passed via environment variables become visible
# through endpoints like /manage/configuration-as-code/viewExport and /manage/systemInfo.
#
# An alternative is using Ansible with Jinja templates to inject secrets into YAML,
# but that approach exposes secrets inside the container in plain text files,
# e.g., /var/jenkins_home/casc_configs/03b-credentials-secrets.yml.
#
# In contrast, this script avoids leaving secrets in config files or exposing them via web endpoints,
# making it a safer (though not perfect) approach for managing Jenkins credentials.

# Helper: Print usage
usage() {
  echo "Usage: $0 --user=<jenkins_user> --url=<jenkins_url> --id=<credentials_id> --type=<type> [options]"
  echo ""
  echo "Supported types: UsernamePassword, SecretText, SSHPrivateKey"
  echo ""
  echo "Required for all types:"
  echo "  --user            Jenkins username"
  echo "  --url             Jenkins base URL"
  echo "  --id              Credential ID"
  echo "  --type            Credential type"
  echo "  --description     Credential description"
  echo ""
  echo "For UsernamePassword:"
  echo "  --username        Username"
  echo "  --password        Password"
  echo ""
  echo "For SecretText:"
  echo "  --secret          Secret string"
  echo ""
  echo "For SSHPrivateKey:"
  echo "  --username        SSH username"
  echo "  --private-key     SSH private key string"
  echo ""
  exit 1
}

# XML generators
generate_username_password_xml() {
cat <<EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>$CREDENTIALS_ID</id>
  <username>$CREDENTIALS_USERNAME</username>
  <password>$CREDENTIALS_PASSWORD</password>
  <description>$CREDENTIALS_DESCRIPTION</description>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF
}

generate_secret_text_xml() {
cat <<EOF
<com.cloudbees.plugins.credentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>$CREDENTIALS_ID</id>
  <secret>$CREDENTIALS_SECRET</secret>
  <description>$CREDENTIALS_DESCRIPTION</description>
</com.cloudbees.plugins.credentials.impl.StringCredentialsImpl>
EOF
}

generate_ssh_private_key_xml() {
cat <<EOF
<com.cloudbees.plugins.credentials.impl.SSHUserPrivateKeyCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>$CREDENTIALS_ID</id>
  <username>$CREDENTIALS_USERNAME</username>
  <privateKey>$CREDENTIALS_PRIVATE_KEY</privateKey>
  <description>$CREDENTIALS_DESCRIPTION</description>
</com.cloudbees.plugins.credentials.impl.SSHUserPrivateKeyCredentialsImpl>
EOF
}

# Parse named args
for arg in "$@"; do
  case $arg in
    --user=*) JENKINS_USER="${arg#*=}" ;;
    --url=*) JENKINS_URL="${arg#*=}" ;;
    --id=*) CREDENTIALS_ID="${arg#*=}" ;;
    --type=*) CREDENTIALS_TYPE="${arg#*=}" ;;
    --description=*) CREDENTIALS_DESCRIPTION="${arg#*=}" ;;
    --username=*) CREDENTIALS_USERNAME="${arg#*=}" ;;
    --password=*) CREDENTIALS_PASSWORD="${arg#*=}" ;;
    --secret=*) CREDENTIALS_SECRET="${arg#*=}" ;;
    --private-key=*) CREDENTIALS_PRIVATE_KEY="${arg#*=}" ;;
    *) echo "Unknown argument: $arg" && usage ;;
  esac
done

# Validate required args
[ -z "$JENKINS_USER" ] && echo "Missing --user" && usage
[ -z "$JENKINS_URL" ] && echo "Missing --url" && usage
[ -z "$CREDENTIALS_ID" ] && echo "Missing --id" && usage
[ -z "$CREDENTIALS_TYPE" ] && echo "Missing --type" && usage
[ -z "$CREDENTIALS_DESCRIPTION" ] && echo "Missing --description" && usage

# Read token
TOKEN_FILE="secrets/${JENKINS_USER}_api_token.txt"
[ ! -f "$TOKEN_FILE" ] && echo "Missing token file: $TOKEN_FILE" && exit 1
JENKINS_USER_API_TOKEN="$(cat "$TOKEN_FILE")"

# --- Check if credential already exists ---
if curl -s -f -u "$JENKINS_USER:$JENKINS_USER_API_TOKEN" \
  "$JENKINS_URL/credentials/store/system/domain/_/credential/$CREDENTIALS_ID/api/json" > /dev/null 2>&1; then
  echo "✅ Credential '$CREDENTIALS_ID' already exists. Skipping creation."
  rm -f "$TMP_XML"
  exit 0
fi

# Generate XML
case "$CREDENTIALS_TYPE" in
  UsernamePassword)
    [ -z "$CREDENTIALS_USERNAME" ] || [ -z "$CREDENTIALS_PASSWORD" ] && echo "Missing --username or --password" && usage
    generate_username_password_xml > credential.xml
    ;;
  SecretText)
    [ -z "$CREDENTIALS_SECRET" ] && echo "Missing --secret" && usage
    generate_secret_text_xml > credential.xml
    ;;
  SSHPrivateKey)
    [ -z "$CREDENTIALS_USERNAME" ] || [ -z "$CREDENTIALS_PRIVATE_KEY" ] && echo "Missing --username or --private-key" && usage
    generate_ssh_private_key_xml > credential.xml
    ;;
  *)
    echo "Unsupported credential type: $CREDENTIALS_TYPE" && usage
    ;;
esac

# POST to Jenkins
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
  -u "$JENKINS_USER:$JENKINS_USER_API_TOKEN" \
  -H "Content-Type: application/xml" \
  --data @credential.xml)

if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "204" ]; then
  echo "✅ Jenkins credential '$CREDENTIALS_ID' created successfully!"
else
  echo "❌ Failed to create Jenkins credential (HTTP $RESPONSE)"
  exit 1
fi


################################ Usage Examples #########################
## UsernamePassword
#./scripts/create_jenkins_credential.sh \
#  --user=ci_user \
#  --url=http://localhost:8080 \
#  --id=github-deploy \
#  --type=UsernamePassword \
#  --username=gituser \
#  --password=secr3t \
#  --description="GitHub deploy credential"
#
## SecretText
#./scripts/create_jenkins_credential.sh \
#  --user=ci_user \
#  --url=http://localhost:8080 \
#  --id=webhook-token \
#  --type=SecretText \
#  --secret=abc123xyz \
#  --description="Webhook token for app A"
#
## SSHPrivateKey
#./scripts/create_jenkins_credential.sh \
#  --user=ci_user \
#  --url=http://localhost:8080 \
#  --id=ssh-access \
#  --type=SSHPrivateKey \
#  --username=ubuntu \
#  --private-key="$(cat ~/.ssh/id_rsa)" \
#  --description="SSH key to EC2 instance"
