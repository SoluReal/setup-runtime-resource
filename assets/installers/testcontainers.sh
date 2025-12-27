#!/bin/bash

function testcontainers_get_dependencies() {
  if [ "$testcontainers_enabled" = "true" ]; then
    echo "ca-certificates curl gawk iproute2 jq lz4 docker-ce docker-ce-cli containerd.io docker-buildx-plugin passwd"
  else
    echo ""
  fi
}
