#!/bin/bash

set -euo pipefail

RECREATE_PIPELINE="${RECREATE_PIPELINE:-false}"

echo "Running setup-runtime tests..."

export PIPELINE_FILE="${PIPELINE_FILE:-pipeline.yml}"

export PIPELINE_NAME="setup-runtime-test"

docker-compose -p concource-resource -f docker-compose.yml build git-server
docker-compose -p concource-resource -f docker-compose.yml up -d

HASH="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8; echo)"

docker buildx build \
  -t localhost:5000/setup-runtime-resource:latest \
  -t localhost:5000/setup-runtime-resource:$HASH \
  --progress=plain \
  --push .

until fly -t test login -c http://localhost:8080 -u test -p test
do
  sleep 5
done

if [[ $RECREATE_PIPELINE = "true" ]]; then
  fly -t test pipelines --json \
    | jq -r ".[] | select(.name==\"$PIPELINE_NAME\") | .name" \
    | xargs -n1 -I{} fly -t test destroy-pipeline -p {} -n
fi

fly -t test set-pipeline -c example/$PIPELINE_FILE -p $PIPELINE_NAME -n \
  --yaml-var "TASK_CONFIG=$(cat example/task.yml)" \
  --yaml-var "SETUP_RUNTIME_SOURCE=$(cat example/runtime-source.yml)
debian_proxy: http://apt-cacher:3142
" \
  --var "setup-runtime-resource-tag=$HASH"

fly -t test unpause-pipeline -p $PIPELINE_NAME

# Clear the cache so we can run 2 jobs, one to verify the cache restore.
fly -t test clear-task-cache -j=setup-runtime-test/test-setup-runtime --step=test-image -c cache -n
# When a new git-server is created all previous versions need to be removed.
echo y | fly -t test clear-versions --resource=setup-runtime-test/example || true

fly -t test trigger-job -j $PIPELINE_NAME/test-setup-runtime --watch

# Second run for cache check.
OUTPUT=$(fly -t test trigger-job -j "$PIPELINE_NAME/test-setup-runtime" --watch 2>&1 | tee /dev/tty)

# Check if "Downloading" appears in the output
if echo "$OUTPUT" | grep -q "Download|Pulling"; then
    echo "Error: 'Downloading' found in logs while the second run should only use caches."
    exit 1
fi
