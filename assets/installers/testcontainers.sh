#!/bin/bash

function testcontainers_get_dependencies() {
  if [ "$testcontainers_enabled" = "true" ]; then
    echo "ca-certificates curl gawk iproute2 jq gzip docker-ce docker-ce-cli containerd.io passwd"
  else
    echo ""
  fi
}
