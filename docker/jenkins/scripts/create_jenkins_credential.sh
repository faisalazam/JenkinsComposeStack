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
#
# DO NOT FORGET TO RUN `scripts/generate_token.sh` BEFORE RUNNING THIS SCRIPT TO GENERATE API TOKEN...

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
  echo ""
  echo "Optional:"
  echo "  --recreate-if-exists If true, will delete the existing credential and then create"
  echo ""
  exit 1
}

generate_username_password_json() {
  echo "{
  \"\": \"0\",
  \"credentials\": {
    \"scope\": \"GLOBAL\",
    \"id\": \"$CREDENTIALS_ID\",
    \"username\": \"$CREDENTIALS_USERNAME\",
    \"password\": \"$CREDENTIALS_PASSWORD\",
    \"description\": \"$CREDENTIALS_DESCRIPTION\",
    \"stapler-class\": \"com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl\"
    }
  }"
}

generate_secret_text_json() {
  echo "{
  \"\": \"0\",
  \"credentials\": {
    \"scope\": \"GLOBAL\",
    \"id\": \"$CREDENTIALS_ID\",
    \"secret\": \"$CREDENTIALS_SECRET\",
    \"description\": \"$CREDENTIALS_DESCRIPTION\",
    \"stapler-class\": \"org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl\"
    }
  }"
}

generate_ssh_private_key_json() {
  # Normalize the private key:
  # - Remove Windows-style carriage returns (\r)
  # - Replace actual newlines with literal \n for JSON string compatibility
  NORMALIZED_PRIVATE_KEY=$(printf '%s' "$CREDENTIALS_PRIVATE_KEY" | sed ':a;N;$!ba;s/\r//g;s/\n/\\n/g')

  # Alternative: Read from file directly (if not already read into a variable)
  # NORMALIZED_PRIVATE_KEY=$(sed ':a;N;$!ba;s/\r//g;s/\n/\\n/g' ./secrets/gitlab_id_rsa)

  echo "{
  \"\": \"0\",
  \"credentials\": {
    \"scope\": \"GLOBAL\",
    \"id\": \"$CREDENTIALS_ID\",
    \"username\": \"$CREDENTIALS_USERNAME\",
    \"description\": \"$CREDENTIALS_DESCRIPTION\",
    \"privateKeySource\": {
      \"stapler-class\": \"com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey\$DirectEntryPrivateKeySource\",
      \"privateKey\": \"$NORMALIZED_PRIVATE_KEY\"
    },
    \"stapler-class\": \"com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey\"
    }
  }"
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
    --recreate-if-exists=*) RECREATE_IF_EXISTS="${arg#*=}" ;;
    *) echo "Unknown argument: $arg" && usage ;;
  esac
done

RECREATE_IF_EXISTS="${RECREATE_IF_EXISTS:-false}"

# Validate required args
[ -z "$JENKINS_USER" ] && echo "Missing --user" && usage
[ -z "$JENKINS_URL" ] && echo "Missing --url" && usage
[ -z "$CREDENTIALS_ID" ] && echo "Missing --id" && usage
[ -z "$CREDENTIALS_TYPE" ] && echo "Missing --type" && usage
[ -z "$CREDENTIALS_DESCRIPTION" ] && echo "Missing --description" && usage

# Read token
TOKEN_FILE="secrets/${JENKINS_USER}_api_token"
[ ! -f "$TOKEN_FILE" ] && echo "Missing token file: $TOKEN_FILE" && exit 1
JENKINS_USER_API_TOKEN="$(cat "$TOKEN_FILE")"

CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_USER_API_TOKEN" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')
CRUMB_FIELD=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')

# Check if CRUMB was retrieved successfully
if [ -z "$CRUMB" ] || [ -z "$CRUMB_FIELD" ]; then
  echo "❌ Failed to fetch CSRF token! Check Jenkins credentials."
  exit 1
fi

# --- Check if credential already exists ---
CRED_URL="$JENKINS_URL/credentials/store/system/domain/_/credential/$CREDENTIALS_ID/api/json"
if curl -s -f -u "$JENKINS_USER:$JENKINS_USER_API_TOKEN" "$CRED_URL" > /dev/null 2>&1; then
  if [ "$RECREATE_IF_EXISTS" = "true" ]; then
    echo "🔁 Credential '$CREDENTIALS_ID' exists. Deleting before re-creating..."
    DELETE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$JENKINS_URL/credentials/store/system/domain/_/credential/$CREDENTIALS_ID/doDelete" \
      -u "$JENKINS_USER:$JENKINS_USER_API_TOKEN")
    if [ "$DELETE_RESPONSE" != "200" ] && [ "$DELETE_RESPONSE" != "302" ]; then
      echo "❌ Failed to delete existing credential (HTTP $DELETE_RESPONSE)"
      exit 1
    fi
  else
    echo "✅ Credential '$CREDENTIALS_ID' already exists. Skipping creation."
    exit 0
  fi
fi

# Generate JSON and store in a variable
case "$CREDENTIALS_TYPE" in
  UsernamePassword)
    [ -z "$CREDENTIALS_USERNAME" ] || [ -z "$CREDENTIALS_PASSWORD" ] && echo "Missing --username or --password" && usage
    CREDENTIALS_JSON=$(generate_username_password_json)
    ;;

  SecretText)
    [ -z "$CREDENTIALS_SECRET" ] && echo "Missing --secret" && usage
    CREDENTIALS_JSON=$(generate_secret_text_json)
    ;;

  SSHPrivateKey)
    [ -z "$CREDENTIALS_USERNAME" ] || [ -z "$CREDENTIALS_PRIVATE_KEY" ] && echo "Missing --username or --private-key" && usage
    CREDENTIALS_JSON=$(generate_ssh_private_key_json)
    ;;

  *)
    echo "Unsupported credential type: $CREDENTIALS_TYPE" && usage
    ;;
esac

# POST to Jenkins with the JSON
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -L \
  -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
  -u "$JENKINS_USER:$JENKINS_USER_API_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "$CRUMB_FIELD: $CRUMB" \
  --data-urlencode "json=$CREDENTIALS_JSON")

if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "204" ]; then
  echo "✅ Jenkins credential '$CREDENTIALS_ID' created successfully!"
else
  echo "❌ Failed to create Jenkins credential (HTTP $RESPONSE)"
  exit 1
fi


################################ Usage Examples #########################
## UsernamePassword
#./scripts/create_jenkins_credential.sh \
#  --user="ci_user" \
#  --url=http://localhost:8080 \
#  --id="github-deploy" \
#  --type=UsernamePassword \
#  --username="gituser" \
#  --password="secr3t" \
#  --description="GitHub deploy credential" \
#  --recreate-if-exists=true
#
## SecretText
#./scripts/create_jenkins_credential.sh \
#  --user="ci_user" \
#  --url=http://localhost:8080 \
#  --id="webhook-token" \
#  --type=SecretText \
#  --secret="abc1&?#@$23xyz" \
#  --description="Webhook token for app A" \
#  --recreate-if-exists=true
#
## SSHPrivateKey
#./scripts/create_jenkins_credential.sh \
#  --user="ci_user" \
#  --url=http://localhost:8080 \
#  --id="ssh-access" \
#  --type=SSHPrivateKey \
#  --username="ubuntu" \
#  --private-key="$(cat ./secrets/gitlab_id_rsa)" \
#  --description="SSH key to EC2 instance" \
#  --recreate-if-exists=true
