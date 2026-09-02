#!/bin/bash

function s3cache_get_dependencies() {
  if [[ "$s3_cache_enabled" = "true" ]]; then
    # Install only what the task needs; curl and unzip are already in the image.
    echo "ca-certificates"
  else
    echo ""
  fi
}
