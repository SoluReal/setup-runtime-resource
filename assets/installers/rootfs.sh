#!/bin/bash

# Runs a command in the rootfs. DEBUG is unset because apt-fast traces every line when it is set.
function rootfs_exec() {
  env -u DEBUG DEBIAN_FRONTEND=noninteractive chroot "$rootfs" "$@"
}

function rootfs_extract_base() {
  mkdir -p "$rootfs"
  tar -x -C "$rootfs" -f "$ROOT_DIR/base.tar"
  mkdir -p "$rootfs/tmp"
  chmod 1777 "$rootfs/tmp"
  # Package scripts and the hook resolve names inside the chroot.
  cp /etc/resolv.conf "$rootfs/etc/resolv.conf"
  rootfs_make_dev
}

# A chroot has no /dev and mounting is not allowed, so create the nodes scripts and the hook need.
function rootfs_make_dev() {
  mkdir -p "$rootfs/dev"
  rm -f "$rootfs"/dev/{null,zero,random,urandom,tty}
  mknod -m 666 "$rootfs/dev/null" c 1 3
  mknod -m 666 "$rootfs/dev/zero" c 1 5
  mknod -m 666 "$rootfs/dev/random" c 1 8
  mknod -m 666 "$rootfs/dev/urandom" c 1 9
  mknod -m 666 "$rootfs/dev/tty" c 5 0
}

# Device nodes don't survive Concourse streaming the rootfs to an unprivileged task.
function rootfs_remove_dev() {
  rm -f "$rootfs"/dev/{null,zero,random,urandom,tty}
}

function rootfs_configure_apt() {
  if [[ -n "${debian_proxy:-}" ]]; then
    echo "Acquire::http { Proxy \"$debian_proxy\"; };" > "$rootfs/etc/apt/apt.conf.d/proxy"
    # apt-fast downloads with aria2, which ignores apt's proxy setting.
    export ARIA2_EXTRA_ARGS="--http-proxy=$debian_proxy"
  fi

  if [[ "$testcontainers_enabled" = "true" && "$testcontainers_rootless" != "true" ]]; then
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

# The base marks aria2 and lockfile-progs auto-installed, so purging apt with --autoremove takes them along.
# The dpkg database, perl and debconf go too: nothing can install packages after this.
function rootfs_remove_installer() {
  rootfs_exec apt-get -y --allow-remove-essential purge --autoremove apt || return
  rm -rf "$rootfs/usr/local/sbin/apt-fast" "$rootfs/etc/apt-fast.conf" "$rootfs/etc/apt" "$rootfs/var/cache/apt" \
    "$rootfs/var/lib/apt" "$rootfs/var/log/apt" "$rootfs/var/log/alternatives.log" "$rootfs/var/log/dpkg.log" \
    "$rootfs"/var/lib/dpkg/* "$rootfs"/etc/dpkg/* "$rootfs"/usr/share/dpkg/* "$rootfs/usr/libexec/dpkg" \
    "$rootfs"/usr/share/perl* "$rootfs"/usr/lib/*-linux-gnu/perl* "$rootfs"/usr/bin/perl* "$rootfs"/usr/bin/debconf* \
    "$rootfs/usr/bin/shasum"
}

# Links the runtime installers create on the host carry the rootfs path in front, which is wrong once it is moved.
function rootfs_fix_symlinks() {
  find "$rootfs" -type l -lname "$rootfs/*" -print0 | while IFS= read -r -d '' link; do
    ln -sfn "$(readlink "$link" | sed "s|^$rootfs||")" "$link"
  done
}
