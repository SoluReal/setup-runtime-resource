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
  rootfs_mount
}

# A chroot has no /dev or /proc. A worker that runs privileged containers in a user namespace forbids mknod of
# devices and mounting a new proc, so bind the container's own (recursively: a user namespace can't split /proc).
ROOTFS_DEVICES=(null zero random urandom tty)

function rootfs_mount() {
  mkdir -p "$rootfs/dev" "$rootfs/proc"
  rootfs_touch_devices
  # An unprivileged resource container lacks CAP_SYS_ADMIN; apt only needs /dev/null to be writable there.
  if ! rootfs_bind_mounts; then
    info "Bind mounts are not permitted here, so the chroot gets empty /dev stand-ins and no /proc."
    rootfs_touch_devices
  fi
}

function rootfs_touch_devices() {
  for device in "${ROOTFS_DEVICES[@]}"; do
    rm -f "$rootfs/dev/$device"
    touch "$rootfs/dev/$device"
  done
}

function rootfs_bind_mounts() {
  for device in "${ROOTFS_DEVICES[@]}"; do
    mount --bind "/dev/$device" "$rootfs/dev/$device" || { rootfs_unmount; return 1; }
  done
  mount --rbind /proc "$rootfs/proc" || { rootfs_unmount; return 1; }
}

# Bind mounts don't survive Concourse streaming the rootfs to a task. Lazy, so a process the hook left behind can't
# fail the build; safe to run twice, as the EXIT trap does after a failure.
function rootfs_unmount() {
  local path
  for path in "${ROOTFS_DEVICES[@]/#/$rootfs/dev/}" "$rootfs/proc"; do
    if grep -qF " $path " /proc/self/mounts; then umount -l "$path"; fi
  done
  for device in "${ROOTFS_DEVICES[@]}"; do rm -f "$rootfs/dev/$device"; done
}

function rootfs_configure_apt() {
  if [[ -n "${debian_proxy:-}" ]]; then
    echo "Acquire::http { Proxy \"$debian_proxy\"; };" > "$rootfs/etc/apt/apt.conf.d/proxy"
    # apt-fast downloads with aria2, which ignores apt's proxy setting.
    export ARIA2_EXTRA_ARGS="--http-proxy=$debian_proxy"
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
  APTCACHE=/var/cache/apt/archives DLDIR=/var/cache/apt/archives/apt-fast rootfs_exec apt-fast -y "$@"
}

# The base marks aria2 and lockfile-progs auto-installed, so autoremove takes them. apt goes only when no installed
# package depends on it: purging it would take those along. The dpkg database, perl and debconf go regardless.
function rootfs_remove_installer() {
  local dependents
  dependents=$(rootfs_exec apt-cache rdepends --installed --no-recommends --no-suggests --no-enhances --no-conflicts \
    --no-breaks --no-replaces apt | tail -n +3) || return
  if [[ -n "$dependents" ]]; then
    rootfs_exec apt-get -y autoremove --purge || return
  else
    rootfs_exec apt-get -y --allow-remove-essential purge --autoremove apt || return
  fi
  rm -rf "$rootfs/usr/local/sbin/apt-fast" "$rootfs/etc/apt-fast.conf" "$rootfs/etc/apt" "$rootfs/var/cache/apt" \
    "$rootfs/var/lib/apt" "$rootfs/var/log/apt" "$rootfs/var/log/alternatives.log" "$rootfs/var/log/dpkg.log" \
    "$rootfs"/var/lib/dpkg/* "$rootfs"/etc/dpkg/* "$rootfs"/usr/share/dpkg/* "$rootfs/usr/libexec/dpkg" \
    "$rootfs"/usr/share/perl* "$rootfs"/usr/lib/*-linux-gnu/perl* "$rootfs"/usr/bin/perl* "$rootfs"/usr/bin/debconf* \
    "$rootfs/usr/bin/shasum"
}

# Links the runtime installers create on the host carry the rootfs path in front, which is wrong once it is moved.
function rootfs_fix_symlinks() {
  find "$rootfs" -xdev -type l -lname "$rootfs/*" -print0 | while IFS= read -r -d '' link; do
    ln -sfn "$(readlink "$link" | sed "s|^$rootfs||")" "$link"
  done
}
