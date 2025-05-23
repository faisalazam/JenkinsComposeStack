#!/bin/sh

CONTAINER_NAME="jenkins"

docker exec "$CONTAINER_NAME" sh -c '
  # Directories to check
  DIRS="${JENKINS_HOME_DIR} /usr/share/jenkins/ref"
  for TARGET_DIR in $DIRS; do
      if [ -d "$TARGET_DIR" ]; then
          # Check if any file is not owned by jenkins
          if find "$TARGET_DIR" ! -user jenkins | grep -q .; then
              echo "❌ Error: Some files in $TARGET_DIR are not owned by jenkins."
              find "$TARGET_DIR" ! -user jenkins -exec ls -ld {} \; | head -n 1
              exit 1
          fi
          echo "✅ Ownership check passed: All files in $TARGET_DIR are owned by jenkins."
      else
          echo "⚠️ Warning: Directory $TARGET_DIR does not exist. Skipping."
      fi
  done

  exit 0
'