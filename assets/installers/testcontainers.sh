#!/bin/bash

function testcontainers_get_dependencies() {
  local shared="curl gawk iproute2 jq passwd"

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

# docker-ce isn't in Debian, so add Docker's repository for the apt install.
function testcontainers_configure_apt() {
  [[ "$testcontainers_enabled" = "true" && "$testcontainers_rootless" != "true" ]] || return 0

  install -m 0755 -d "$rootfs/etc/apt/keyrings"
  curl_retry -fsSL https://download.docker.com/linux/debian/gpg -o "$rootfs/etc/apt/keyrings/docker.asc"
  chmod a+r "$rootfs/etc/apt/keyrings/docker.asc"

  cat > "$rootfs/etc/apt/sources.list.d/docker.sources" <<SOURCES
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. "$rootfs/etc/os-release" && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
}
