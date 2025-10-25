#!/bin/bash

set -e

echo "Running setup-runtime tests..."

export PIPELINE_FILE="${PIPELINE_FILE:-pipeline.yml}"
export PIPELINE_NAME="setup-runtime-test"

fly -t test set-pipeline -c example/$PIPELINE_FILE -p $PIPELINE_NAME -n

fly -t test unpause-pipeline -p $PIPELINE_NAME

fly -t test trigger-job -j $PIPELINE_NAME/test-setup-runtime --watch
