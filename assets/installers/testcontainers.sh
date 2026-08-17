#!/bin/bash

function testcontainers_get_dependencies() {
  if [ "$testcontainers_enabled" = "true" ]; then
    # lz4 is not needed here: docker image caching stores raw tarballs since layers are already compressed.
    echo "ca-certificates curl gawk iproute2 jq docker-ce docker-ce-cli containerd.io docker-buildx-plugin passwd"
  else
    echo ""
  fi
}
