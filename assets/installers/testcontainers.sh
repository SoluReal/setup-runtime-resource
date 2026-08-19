#!/bin/bash

function testcontainers_get_dependencies() {
  # Needed by both runtimes.
  local shared="ca-certificates curl gawk iproute2 jq passwd"

  if [ "$testcontainers_enabled" = "true" ]; then
    if [ "$testcontainers_rootless" = "true" ]; then
      # podman-docker provides a `docker` CLI shim; fuse-overlayfs/passt/uidmap are
      # what let podman run fully rootless (no dockerd, no real root). passt provides
      # pasta, podman's rootless network backend.
      echo "$shared podman podman-docker fuse-overlayfs passt uidmap"
    else
      echo "$shared docker-ce docker-ce-cli containerd.io docker-buildx-plugin"
    fi
  else
    echo ""
  fi
}
