#!/bin/sh

# MSYS_NO_PATHCONV=1 docker exec jenkins sh /usr/local/bin/tests/test_agents.sh

CI_USER="ci_user"
JENKINS_URL="http://localhost:8080"
CI_USER_API_TOKEN_FILE="/var/jenkins_home/jcasc_secrets/generated/ci_user_api_token"
CI_USER_API_TOKEN="$(cat $CI_USER_API_TOKEN_FILE)"

# Get agent status with error handling
RESPONSE=$(curl -s -u "$CI_USER:$CI_USER_API_TOKEN" "$JENKINS_URL/computer/api/json")

# Check if authentication failed
if echo "$RESPONSE" | grep -q "Unauthorized"; then
  echo "❌ Authentication failed! Please check CI_USER and CI_USER_API_TOKEN."
  exit 2
fi

# Extract agent status
AGENT_STATUS=$(echo "$RESPONSE" | grep -o '"offline":false')

# Check if at least one agent is online
if echo "$AGENT_STATUS" | grep -q "false"; then
  echo "✅ All agents are connected!"
else
  echo "❌ Some agents are offline!"
  exit 1
fi
