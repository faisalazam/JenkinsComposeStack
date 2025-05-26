#!/bin/sh

# MSYS_NO_PATHCONV=1 docker exec jenkins sh /usr/local/bin/scripts/generate_token.sh

CI_USER="ci_user"
TOKEN_NAME="ci_user_api_token"
JENKINS_URL="http://localhost:8080"
COOKIE_JAR="/var/jenkins_home/jcasc_secrets/generated/cookies"
CI_USER_PASSWORD_FILE="/var/jenkins_home/jcasc_secrets/ci_user_password"
CI_USER_API_TOKEN_FILE="/var/jenkins_home/jcasc_secrets/generated/ci_user_api_token"
CI_USER_PASSWORD="$(base64 -d "$CI_USER_PASSWORD_FILE")"

mkdir -p "/var/jenkins_home/jcasc_secrets/generated"

# Fetch CSRF token
CRUMB_JSON=$(curl -c "$COOKIE_JAR" -s -u "$CI_USER:$CI_USER_PASSWORD" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')
CRUMB_FIELD=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')

# Generate API token using session cookies
RESPONSE=$(curl -b "$COOKIE_JAR" -X POST "$JENKINS_URL/user/$CI_USER/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken" \
    -u "$CI_USER:$CI_USER_PASSWORD" \
    -H "$CRUMB_FIELD:$CRUMB" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data "newTokenName=$TOKEN_NAME")

# Extract token value using sed
TOKEN_VALUE=$(echo "$RESPONSE" | sed -n 's/.*"tokenValue":"\([^"]*\)".*/\1/p')

if [ -n "$TOKEN_VALUE" ]; then
    echo "$TOKEN_VALUE" > "$CI_USER_API_TOKEN_FILE"
    chmod 600 "$CI_USER_API_TOKEN_FILE"
    echo "✅ API token saved to $CI_USER_API_TOKEN_FILE"
else
    echo "❌ Failed to extract API token"
    exit 1
fi
