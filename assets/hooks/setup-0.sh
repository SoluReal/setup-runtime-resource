#!/bin/bash

# inspired by: https://github.com/deepin-community/mmdebstrap/blob/574048f2a720057b75e56622003932f344dc700a/hooks/copy-host-apt-sources-and-preferences/setup00.sh#L3

set -eo pipefail

chroot_dir="$1"
source $ROOT_DIR/common.sh

log_info_hook "Installing dependencies"

if [[ "$testcontainers_enabled" = "true" ]]; then
  SOURCEPARTS="/etc/apt/sources.d/"
  eval "$(apt-config shell SOURCEPARTS Dir::Etc::SourceParts/d)"

  f="$SOURCEPARTS"/docker.sources
  mkdir --parents "$(dirname "$chroot_dir/$f")"
  cat "$f" >> "$chroot_dir/$f"
fi

mkdir -p "$chroot_dir/$RUNTIME_DIR/plugins"
