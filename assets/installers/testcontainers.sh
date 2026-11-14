#!/bin/bash

function testcontainers_get_dependencies() {
  local shared="ca-certificates curl gawk iproute2 jq passwd"

  if [ "$testcontainers_enabled" = "true" ]; then
    if [ "$testcontainers_rootless" = "true" ]; then
      # podman-docker shims `docker`; fuse-overlayfs/passt/uidmap enable rootless (passt provides
      # pasta, the rootless network backend).
      echo "$shared podman podman-docker fuse-overlayfs passt uidmap nftables"
    else
      echo "$shared docker-ce docker-ce-cli containerd.io docker-buildx-plugin"
    fi
  else
    echo ""
  fi
}
