#!/bin/sh

# MSYS_NO_PATHCONV=1 docker exec jenkins sh /usr/local/bin/tests/test_jobs.sh

MAX_RETRIES=120
RETRY_INTERVAL=2  # seconds
CI_USER="ci_user"
JENKINS_URL="http://localhost:8080"
JOB_NAME="jenkins-sanity-check-pipeline"
CI_USER_API_TOKEN_FILE="/var/jenkins_home/jcasc_secrets/generated/ci_user_api_token"
CI_USER_API_TOKEN="$(cat $CI_USER_API_TOKEN_FILE)"

# Fetch CSRF token
CRUMB_JSON=$(curl -s -u "$CI_USER:$CI_USER_API_TOKEN" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')
CRUMB_FIELD=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')

# Check if CRUMB was retrieved successfully
if [ -z "$CRUMB" ] || [ -z "$CRUMB_FIELD" ]; then
  echo "❌ Failed to fetch CSRF token! Check Jenkins credentials."
  exit 1
fi

LAST_BUILD_JSON=$(curl -s -u "$CI_USER:$CI_USER_API_TOKEN" "$JENKINS_URL/job/$JOB_NAME/lastBuild/api/json")
LAST_BUILD_NUMBER=$(echo "$LAST_BUILD_JSON" | sed -n 's/.*"number":\([0-9]\+\).*"previousBuild".*/\1/p')
LAST_BUILD_NUMBER=${LAST_BUILD_NUMBER:-0}  # Default to 0 if empty

# Trigger job with
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -u "$CI_USER:$CI_USER_API_TOKEN" \
    -H "Content-Type: application/json" \
    -H "$CRUMB_FIELD: $CRUMB" \
    "$JENKINS_URL/job/$JOB_NAME/build")

if [ "$RESPONSE" -eq 403 ]; then
  echo "❌ Authentication failed! Check Jenkins credentials. HTTP Response: $RESPONSE"
  exit 1
elif [ "$RESPONSE" -ne 201 ]; then
  echo "❌ Failed to trigger job '$JOB_NAME'. HTTP Response: $RESPONSE"
  exit 1
fi

echo "✅ Job '$JOB_NAME' triggered successfully. Waiting for it to start..."

# Retry logic to get the build number
attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
    BUILD_JSON=$(curl -s -u "$CI_USER:$CI_USER_API_TOKEN" "$JENKINS_URL/job/$JOB_NAME/lastBuild/api/json")
    BUILD_NUMBER=$(echo "$BUILD_JSON" | sed -n 's/.*"number":\([0-9]\+\).*"previousBuild".*/\1/p')

    if [ -n "$BUILD_NUMBER" ] && [ "$BUILD_NUMBER" -gt "$LAST_BUILD_NUMBER" ]; then
        echo "🔎 New build detected! Build number: $BUILD_NUMBER"
        break
    fi

    attempt=$((attempt + 1))
    echo "⏳ Waiting for build to start... ($attempt/$MAX_RETRIES)"
    sleep "$RETRY_INTERVAL"
done

if [ -z "$BUILD_NUMBER" ]; then
    echo "❌ Could not fetch the last build number. Something went wrong."
    exit 1
fi

# Wait for job completion
echo "🔎 Monitoring status of Build #$BUILD_NUMBER ..."

attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
    BUILD_STATUS=$(curl -s -u "$CI_USER:$CI_USER_API_TOKEN" "$JENKINS_URL/job/$JOB_NAME/$BUILD_NUMBER/api/json" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$BUILD_STATUS" ]; then
        if [ "$BUILD_STATUS" = "SUCCESS" ]; then
            echo "✅ Job '$JOB_NAME' (Build #$BUILD_NUMBER) completed successfully!"
            exit 0
        else
            echo "❌ Job '$JOB_NAME' (Build #$BUILD_NUMBER) failed!"

            # Fetch and display logs for debugging
            echo "📜 Fetching logs for Build #$BUILD_NUMBER..."
            curl -s -u "$CI_USER:$CI_USER_API_TOKEN" "$JENKINS_URL/job/$JOB_NAME/$BUILD_NUMBER/consoleText" | tail -n 20

            exit 1
        fi
    fi

    attempt=$((attempt + 1))
    echo "⏳ Build is still running... ($attempt/$MAX_RETRIES)"
    sleep "$RETRY_INTERVAL"
done

echo "❌ Timeout reached. Build did not complete in expected time."
exit 1
