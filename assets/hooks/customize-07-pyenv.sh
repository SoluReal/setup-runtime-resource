#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

if [[ "$pyenv_enabled" = "true" ]]; then
  export PYENV_ROOT="$chroot_dir$PYENV_RUNTIME_DIR"
  mkdir -p "$PYENV_ROOT"

  curl -fsSL https://github.com/pyenv/pyenv/archive/refs/tags/v2.6.17.tar.gz \
    | tar -xz --strip-components=1 -C "$PYENV_ROOT" &
  info_spinner "Installing pyenv" "pyenv installed" $!

  echo "unset ENV" >> $chroot_dir/root/.bashrc
  echo "unset BASH_ENV" >> $chroot_dir/root/.bashrc
  echo "export PYENV_ROOT=$PYENV_RUNTIME_DIR" >> $chroot_dir/root/.bashrc
  echo "[[ -d \$PYENV_ROOT/bin ]] && export PATH=\"\$PYENV_ROOT/bin:\$PATH\"" >> $chroot_dir/root/.bashrc

  set_env "PYENV_ENABLED=true"
  add_metadata "pyenv" "true"
fi
