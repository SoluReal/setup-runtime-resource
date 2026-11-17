#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

# mmdebstrap's own apt step then finds the debs in the archive cache instead of downloading
# them one by one. Not in the rootfs, so nothing needs removing afterwards.
if [[ -n "${MMDEBSTRAP_INCLUDE:-}" ]]; then
  info_to_output_file "Downloading packages in parallel"
  # apt-fast joins Dir and Dir::Cache without a slash, so name the archive dirs itself.
  # _APTMGR=true skips its closing apt-get run, which would refetch what the rename below fixes.
  APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" APTCACHE="$chroot_dir/var/cache/apt/archives" _APTMGR=true \
    DLDIR="$chroot_dir/var/cache/apt/archives/apt-fast" apt-fast -y -d install --no-install-recommends \
    ${MMDEBSTRAP_INCLUDE//,/ }

  # apt-fast saves debs without their epoch ("git_2.47.3" for 1:2.47.3), which apt would not find.
  archives="$chroot_dir/var/cache/apt/archives"
  for deb in "$archives"/*.deb; do
    version=$(dpkg-deb -f "$deb" Version)
    [[ "$version" == *:* ]] || continue
    name=$(dpkg-deb -f "$deb" Package)_${version//:/%3a}_$(dpkg-deb -f "$deb" Architecture).deb
    mv -f "$deb" "$archives/$name"
  done
fi
