#!/bin/bash

# Reset
Color_Off='\033[0m' # Text Reset

# To print to console with colors
Red='\033[0;31m'    # Red
Green='\033[0;32m'  # Green

RUNTIME_DIR="/opt/runtimes"
SDKMAN_DIR="$RUNTIME_DIR/sdkman"
WORK_ROOTFS="/tmp/work-rootfs"

# Compute a deterministic hash of the .source from stdin JSON
compute_hash() {
  local json="$1"
  echo "$json" | jq -c .source | sha256sum | awk '{print $1}'
}

function info() {
  printf "$Green[setup-runtime] %s$Color_Off\n" "$1"
}
function error() {
  printf "$Red[setup-runtime] %s$Color_Off\n" "$1" >&2
}

# Mount standard filesystems for chroot operations
mount_chroot() {
  local rootfs="${1:-$WORK_ROOTFS}"
  mkdir -p "$rootfs"{,/proc,/sys,/dev,/dev/pts}
  mountpoint -q "$rootfs/proc" || mount -t proc proc "$rootfs/proc"
  mountpoint -q "$rootfs/sys" || mount -t sysfs sys "$rootfs/sys"
  mountpoint -q "$rootfs/dev" || mount --bind /dev "$rootfs/dev"
  mountpoint -q "$rootfs/dev/pts" || mount --bind /dev/pts "$rootfs/dev/pts"
}

umount_chroot() {
  local rootfs="${1:-$WORK_ROOTFS}"
  # Unmount in reverse order, ignore errors
  umount -l "$rootfs/dev/pts" 2>/dev/null || true
  umount -l "$rootfs/dev" 2>/dev/null || true
  umount -l "$rootfs/sys" 2>/dev/null || true
  umount -l "$rootfs/proc" 2>/dev/null || true
}

# Execute a command inside the rootfs using chroot
chroot_exec() {
  local rootfs="${1:-$WORK_ROOTFS}"
  shift
  local cmd="$*"
  chroot "$rootfs" /bin/bash -lc "source /root/.bashrc >/dev/null 2>&1 || true; $cmd"
}

# Copy file or directory into rootfs at a path
rootfs_copy() {
  local rootfs="${1:-$WORK_ROOTFS}"
  local src_path="${2}"
  local dest_path="${3}"
  mkdir -p "${rootfs}$(dirname "$dest_path")"
  if [ -d "$src_path" ]; then
    cp -a "$src_path/." "${rootfs}${dest_path}"
  else
    cp -a "$src_path" "${rootfs}${dest_path}"
  fi
}

function set_env() {
  local ctr_or_rootfs="${1}"
  local env_line="${2}"

  touch /tmp/env_vars
  echo "$env_line" >> /tmp/env_vars

  # Persist into bashrc inside rootfs
  local rootfs="$ctr_or_rootfs"
  mkdir -p "$rootfs/root"
  touch "$rootfs/root/.bashrc"

  # If contains '&&', split into KEY=VALUE and extra commands
  if [[ "$env_line" == *"&&"* ]]; then
    local kv_part=$(echo "$env_line" | awk -F '&&' '{print $1}' | xargs)
    local extra_part=$(echo "$env_line" | cut -d'&' -f3- | sed 's/^ *//')
    if [[ "$kv_part" == *=* ]]; then
      echo "export $kv_part" >> "$rootfs/root/.bashrc"
    else
      echo "$kv_part" >> "$rootfs/root/.bashrc"
    fi
    # Append the extra commands as-is
    echo "$extra_part" >> "$rootfs/root/.bashrc"
  else
    if [[ "$env_line" == *=* ]]; then
      echo "export $env_line" >> "$rootfs/root/.bashrc"
    else
      echo "$env_line" >> "$rootfs/root/.bashrc"
    fi
  fi
}

function add_metadata() {
  local key="${1}"
  local value="${2}"

  touch /tmp/metadata
  echo "{\"name\": \"$key\", \"value\": \"$value\"}" >> /tmp/metadata
}

function log_on_error() {
  if [ "$VERBOSE" = "true" ]; then
    "$@"
  else
    local tmp
    tmp=$(mktemp)

    set +e
    "$@" >"$tmp" 2>&1
    local status=$?
    set -e

     if [ $status -ne 0 ]; then
        cat "$tmp"
        rm -f "$tmp"
        error "failed to setup-runtime. You can set verbose: true to enable more verbose logging."
        exit $status
      fi

    rm -f "$tmp"

    return $status
  fi
}
