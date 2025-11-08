#!/bin/bash

set -e

echo "Running setup-runtime tests..."

export PIPELINE_FILE="${PIPELINE_FILE:-pipeline.yml}"

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

export PIPELINE_NAME="setup-runtime-test"

fly -t test pipelines --json \
  | jq -r ".[] | select(.name==\"$PIPELINE_NAME\") | .name" \
  | xargs -n1 -I{} fly -t test destroy-pipeline -p {} -n

fly -t test set-pipeline -c example/$PIPELINE_FILE -p $PIPELINE_NAME -n\
  --yaml-var "TASK_CONFIG=$(cat example/task.yml)"

fly -t test unpause-pipeline -p $PIPELINE_NAME

fly -t test trigger-job -j $PIPELINE_NAME/test-setup-runtime --watch
