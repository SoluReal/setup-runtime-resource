#!/bin/bash

set -euo pipefail

BUILD="${BUILD:-false}"

echo "Running setup-runtime tests..."

export PIPELINE_FILE="${PIPELINE_FILE:-pipeline.yml}"

export PIPELINE_NAME="setup-runtime-test"

if [ "$BUILD" = "true" ]; then
  docker-compose -p concource-resource -f docker-compose.yml down
  docker-compose -p concource-resource -f docker-compose.yml up -d

  docker buildx build \
    -t localhost:5000/setup-runtime-resource:latest \
    --progress=plain \
    --push .

  until fly -t test login -c http://localhost:8080 -u test -p test
  do
    sleep 5
  done

  fly -t test pipelines --json \
    | jq -r ".[] | select(.name==\"$PIPELINE_NAME\") | .name" \
    | xargs -n1 -I{} fly -t test destroy-pipeline -p {} -n
fi

fly -t test set-pipeline -c example/$PIPELINE_FILE -p $PIPELINE_NAME -n\
  --yaml-var "TASK_CONFIG=$(cat example/task.yml)" \
  --yaml-var "SETUP_RUNTIME_SOURCE=$(cat example/runtime-source.yml)"

fly -t test unpause-pipeline -p $PIPELINE_NAME

fly -t test trigger-job -j $PIPELINE_NAME/test-setup-runtime --watch

# Second run for cache check.
OUTPUT=$(fly -t test trigger-job -j "$PIPELINE_NAME/test-setup-runtime" --watch 2>&1 | tee /dev/tty)

# Check if "Downloading" appears in the output
if echo "$OUTPUT" | grep -q "Download|Pulling"; then
    echo "Error: 'Downloading' found in logs while the second run should only use caches."
    exit 1
fi
