#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

# renovate: datasource=github-releases depName=astral-sh/uv
UV_VERSION=0.13.9

if runtime_is_requested_in_source python; then
  uv_dir="$chroot_dir$UV_RUNTIME_DIR"

  # UV_UNMANAGED_INSTALL skips the receipt and shell-profile edits, which would land on the host.
  (
    curl_retry -LsSf "https://astral.sh/uv/$UV_VERSION/install.sh" | env UV_UNMANAGED_INSTALL="$uv_dir/bin" sh
  ) &
  info_spinner "Installing uv $UV_VERSION" "uv installed" $!

  # uv.enabled alone installs no interpreter, so a task picks one with .python-version.
  if [[ -n "$python_version" ]]; then
    (
      PATH="$uv_dir/bin:$PATH" UV_PYTHON_INSTALL_DIR="$uv_dir/python" UV_PYTHON_BIN_DIR="$uv_dir/bin" UV_NO_CACHE=1 \
        uv python install "$python_version" --default --preview-features python-install-default
      # uv links by absolute path, and this hook runs outside the chroot.
      find "$uv_dir" -type l | while read -r link; do
        target=$(readlink "$link")
        if [[ "$target" == "$chroot_dir"/* ]]; then ln -sfn "${target#"$chroot_dir"}" "$link"; fi
      done
    ) &
    info_spinner "Installing Python $python_version" "Python installed" $!

    # The install dir is named cpython-<x.y.z>-<platform>, next to a cpython-<x.y>-<platform> link.
    resolved=$(find "$uv_dir/python" -maxdepth 1 -type d -name 'cpython-*.*.*-*' -printf '%f\n' | head -1)
    resolved=${resolved#cpython-}
    add_metadata "python" "${resolved%%-*}"
  fi

  mkdir -p "$chroot_dir$RUNTIME_DIR/plugins"
  cp "$ROOT_DIR/includes/uv.sh" "$chroot_dir$RUNTIME_DIR/plugins/uv.sh"
fi
