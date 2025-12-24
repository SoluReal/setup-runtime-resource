#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

if [[ -n "$nodejs_version" || "$nvm_enabled" = "true" ]]; then
  export NVM_DIR="$chroot_dir$NVM_RUNTIME_DIR"
  mkdir -p "$NVM_DIR"

  PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' &
  info_spinner "Installing nvm (node version manager)" "nvm installed (node version manager)" $!

  echo "export NVM_DIR=$NVM_RUNTIME_DIR; source \$NVM_DIR/nvm.sh" >> $chroot_dir/root/.bashrc
  echo "export COREPACK_HOME=$COREPACK_HOME_DIR" >> $chroot_dir/root/.bashrc
fi
if [[ "$nvm_enabled" = "true" ]]; then
  set_env "NVM_ENABLED=true"
  add_metadata "nvm" "true"
fi
