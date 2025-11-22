#!/bin/bash

# inspired by: https://github.com/deepin-community/mmdebstrap/blob/574048f2a720057b75e56622003932f344dc700a/hooks/copy-host-apt-sources-and-preferences/setup00.sh#L3

set -eu

rootdir="$1"

if [[ "$testcontainers_enabled" = "true" ]]; then
  SOURCEPARTS="/etc/apt/sources.d/"
  eval "$(apt-config shell SOURCEPARTS Dir::Etc::SourceParts/d)"

  f="$SOURCEPARTS"/docker.sources
  mkdir --parents "$(dirname "$rootdir/$f")"
  cat "$f" >> "$rootdir/$f"
fi
