#!/bin/bash

function testcontainers_get_dependencies() {
  local shared="curl gawk iproute2 jq passwd"

  [[ "$testcontainers_enabled" = "true" ]] || return 0
  if testcontainers_uses_docker; then
    echo "$shared docker-ce docker-ce-cli containerd.io docker-buildx-plugin"
  else
    # podman-docker shims `docker`; fuse-overlayfs/passt/uidmap enable rootless (passt provides
    # pasta, the rootless network backend).
    echo "$shared podman podman-docker fuse-overlayfs passt uidmap nftables"
  fi
}

# docker-ce isn't in Debian, so add Docker's repository for the apt install.
function testcontainers_configure_apt() {
  testcontainers_uses_docker || return 0

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
