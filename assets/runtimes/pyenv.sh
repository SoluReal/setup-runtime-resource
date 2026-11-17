#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

if runtime_wanted pyenv; then
  export PYENV_ROOT="$chroot_dir$PYENV_RUNTIME_DIR"
  mkdir -p "$PYENV_ROOT"

  (
    archive=$(mktemp)
    curl_retry -fsSL https://github.com/pyenv/pyenv/archive/refs/tags/v2.6.17.tar.gz -o "$archive"
    tar -xzf "$archive" --strip-components=1 -C "$PYENV_ROOT"
    rm -f "$archive"
  ) &
  info_spinner "Installing pyenv" "pyenv installed" $!

  echo "export PYENV_ROOT=$PYENV_RUNTIME_DIR" >> "$RUNTIME_BASHRC"
  echo "[[ -d \$PYENV_ROOT/bin ]] && export PATH=\"\$PYENV_ROOT/bin:\$PATH\"" >> "$RUNTIME_BASHRC"

  add_task_env_var "PYENV_ENABLED=true"
  add_metadata "pyenv" "true"
fi
