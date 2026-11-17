#!/bin/bash

# apk runs from the host: it installs into the rootfs and chroots only for package scripts.
APK_CACHE=/tmp/apk-cache
function rootfs_apk() {
  env -u DEBUG apk --root "$rootfs" --cache-dir "$APK_CACHE" "$@"
}

function rootfs_extract_base() {
  mkdir -p "$rootfs"
  zstd -dc "$ROOT_DIR/base.tar.zst" | tar -x -C "$rootfs"
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

function rootfs_install_dependencies() {
  # log_on_error runs these with errexit off, so each step has to fail the function itself.
  mkdir -p "$APK_CACHE"
  rootfs_apk update || return
  rootfs_prefetch "$1" || return
  # Wolfi is rolling: the base is as old as the image, so upgrade it (security fixes) first.
  rootfs_apk upgrade --available || return
  # shellcheck disable=SC2086
  [[ -z "$1" ]] || rootfs_apk add $1
}

# apk downloads one package at a time. Fetch them in parallel into its cache instead, under the name
# `<package>-<version>.<first 8 hex of the index checksum>.apk` that apk looks up (Wolfi packages carry no signature).
function rootfs_prefetch() {
  local wanted="$APK_CACHE/wanted" index repo arch
  # shellcheck disable=SC2086
  { rootfs_apk upgrade --available --simulate; [[ -z "$1" ]] || rootfs_apk add --simulate $1; } \
    | sed -n -e 's/^.*Installing \(.*\) (\(.*\))$/\1-\2/p' -e 's/^.*Upgrading \(.*\) (.* -> \(.*\))$/\1-\2/p' \
    | sort -u > "$wanted"
  index=$(ls "$APK_CACHE"/APKINDEX.*.tar.gz)
  repo=$(head -1 "$rootfs/etc/apk/repositories")
  arch=$(cat "$rootfs/etc/apk/arch")
  tar -xzOf "$index" APKINDEX | awk -v wanted="$wanted" '
    BEGIN { while ((getline line < wanted) > 0) want[line] = 1 }
    /^P:/ { name = substr($0, 3) }
    /^V:/ { ver = substr($0, 3) }
    /^C:Q1/ { sum = substr($0, 5) }
    /^$/ { if ((name "-" ver) in want) print name "-" ver, sum; name = ver = sum = "" }' \
    | while read -r package sum; do
        # shellcheck disable=SC2154
        printf 'url = %s/%s/%s.apk\noutput = %s/%s.%s.apk\n' "$repo" "$arch" "$package" "$APK_CACHE" "$package" \
          "$(printf '%s' "$sum" | base64 -d | od -An -tx1 -N4 | tr -d ' \n')"
      done > "$APK_CACHE/downloads"
  # Nothing to fetch when the simulation failed; the install below then reports why.
  [[ -s "$APK_CACHE/downloads" ]] || return 0
  curl_retry -sS -L -Z --parallel-max 16 --fail -K "$APK_CACHE/downloads"
}

# Nothing can install packages in the final rootfs: the hook and tasks get what `dependencies` lists.
function rootfs_remove_installer() {
  rm -rf "$rootfs"/etc/apk "$rootfs"/usr/lib/apk "$APK_CACHE"
}

# Links the runtime installers create on the host carry the rootfs path in front, which is wrong once it is moved.
function rootfs_fix_symlinks() {
  find "$rootfs" -type l -lname "$rootfs/*" -print0 | while IFS= read -r -d '' link; do
    ln -sfn "$(readlink "$link" | sed "s|^$rootfs||")" "$link"
  done
}
