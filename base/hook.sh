#!/bin/bash
# mmdebstrap hooks for the base rootfs: $1 = hook name, $2 = rootfs directory.
set -eo pipefail

essential_list=/tmp/setup-runtime-essential

case "$1" in
  # Before apt is installed: remember what the bare essential rootfs is made of.
  essential)
    dpkg-query --admindir="$2/var/lib/dpkg" -W -f '${Package}\n' > "$essential_list"
    ;;
  # Everything else exists only to run apt-fast; `in` autoremoves it once the dependencies are in.
  customize)
    # shellcheck disable=SC2046
    chroot "$2" apt-mark auto $(dpkg-query --admindir="$2/var/lib/dpkg" -W -f '${Package}\n' \
      | grep -vxFf "$essential_list")
    ;;
esac
