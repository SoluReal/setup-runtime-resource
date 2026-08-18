#!/bin/bash

function testcontainers_get_dependencies() {
  if [ "$testcontainers_enabled" = "true" ]; then
    if [ "$testcontainers_rootless" = "true" ]; then
      # podman-docker provides a `docker` CLI shim; fuse-overlayfs/slirp4netns/uidmap
      # are what let podman run fully rootless (no dockerd, no real root).
      echo "ca-certificates curl gawk iproute2 jq podman podman-docker fuse-overlayfs slirp4netns passt uidmap passwd"
    else
      # lz4 is not needed here: docker image caching stores raw tarballs since layers are already compressed.
      echo "ca-certificates curl gawk iproute2 jq docker-ce docker-ce-cli containerd.io docker-buildx-plugin passwd"
    fi
  else
    echo ""
  fi
}
