#!/bin/bash

# Runs a command in the rootfs. DEBUG is unset because apt-fast traces every line when it is set.
function rootfs_exec() {
  env -u DEBUG DEBIAN_FRONTEND=noninteractive fakechroot chroot "$rootfs" "$@"
}

function rootfs_extract_base() {
  mkdir -p "$rootfs"
  # The base's apt state is dropped (`apt-get update` recreates it) and /tmp is made fresh.
  tar -x --zstd -C "$rootfs" -f "$ROOT_DIR/base.tar.zst" --exclude=./var/cache/apt --exclude=./var/lib/apt/lists --exclude=./tmp
  mkdir -p "$rootfs/tmp"
  chmod 1777 "$rootfs/tmp"
}

function rootfs_configure_apt() {
  # fakechroot resolves names through the rootfs, so it needs the host's resolver config.
  cp /etc/resolv.conf "$rootfs/etc/resolv.conf"

  if [[ -n "${debian_proxy:-}" ]]; then
    echo "Acquire::http { Proxy \"$debian_proxy\"; };" > "$rootfs/etc/apt/apt.conf.d/proxy"
    # apt-fast downloads with aria2, which ignores apt's proxy setting.
    export ARIA2_EXTRA_ARGS="--all-proxy=$debian_proxy"
  fi

  if [[ "$testcontainers_enabled" = "true" && "$testcontainers_rootless" != "true" ]]; then
    install -m 0755 -d "$rootfs/etc/apt/keyrings"
    curl_retry -fsSL https://download.docker.com/linux/debian/gpg -o "$rootfs/etc/apt/keyrings/docker.asc"
    chmod a+r "$rootfs/etc/apt/keyrings/docker.asc"

    cat > "$rootfs/etc/apt/sources.list.d/docker.sources" <<SOURCES
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $DEBIAN_VERSION
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
  fi
}

function rootfs_install_dependencies() {
  # log_on_error runs these with errexit off, so each step has to fail the function itself.
  rootfs_exec apt-get update || return
  # The base is as old as the image, so bring its packages up to date (security fixes) first.
  rootfs_apt_fast upgrade || return
  # shellcheck disable=SC2086
  rootfs_apt_fast install --no-install-recommends $1
}

# apt-fast joins two apt directories without a slash, so name the archives itself.
function rootfs_apt_fast() {
  APTCACHE=/var/cache/apt/archives DLDIR=/var/cache/apt/archives/apt-fast \
    rootfs_exec apt-fast -y -o Dpkg::Options::=--force-unsafe-io "$@"
}

# The base keeps apt, aria2 and their libraries marked auto-installed, so purging apt (which
# apt-get never autoremoves itself and holds essential) with --autoremove leaves what mmdebstrap's essential variant gave.
function rootfs_remove_installer() {
  rootfs_exec apt-get -y --allow-remove-essential purge --autoremove apt || return
  rm -rf "$rootfs/usr/local/sbin/apt-fast" "$rootfs/etc/apt-fast.conf" "$rootfs/var/cache/apt" \
    "$rootfs/var/cache/debconf/tmp.ci" "$rootfs/var/lib/apt" "$rootfs/var/log/apt" \
    "$rootfs/var/log/alternatives.log" "$rootfs/var/log/dpkg.log"
}

# fakechroot writes symlink targets with the rootfs path in front, which is wrong once it is moved.
function rootfs_fix_symlinks() {
  find "$rootfs" -type l -lname "$rootfs/*" -print0 | while IFS= read -r -d '' link; do
    ln -sfn "$(readlink "$link" | sed "s|^$rootfs||")" "$link"
  done
}
