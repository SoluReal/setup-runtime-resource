#!/bin/bash

set -e

chroot_dir="$1"
source $ROOT_DIR/common.sh

if [ -n "$nodejs_version" ]; then
  if [ "$nodejs_version" = "lts" ]; then
    candidate="--lts"
  else
    candidate="$nodejs_version"
  fi

  export NVM_DIR="$chroot_dir$NVM_RUNTIME_DIR"
  mkdir -p $NVM_DIR

  # TODO -as- 20251119 renovate
  PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' &
  info_spinner "Installing nvm (node version manager)" "nvm installed (node version manager)" $!

  echo "export NVM_DIR=$NVM_RUNTIME_DIR; source \$NVM_DIR/nvm.sh" >> $chroot_dir/root/.bashrc
  echo "export COREPACK_HOME=$COREPACK_HOME_DIR" >> $chroot_dir/root/.bashrc

  source $NVM_DIR/nvm.sh

  nvm install $candidate
  add_metadata "node" "$(nvm current)"
  npm uninstall -g yarn pnpm || true

  export COREPACK_HOME="$chroot_dir/$COREPACK_HOME_DIR"
  if [[ -n "$yarn_version" || -n "$pnpm_version" ]]; then
    npm install -g corepack &
    info_spinner "Installing corepack" "Corepack installed" $!
  fi

  if [ -n "$yarn_version" ]; then
    corepack prepare yarn@${yarn_version} --activate &
    info_spinner "Installing yarn $yarn_version" "yarn $yarn_version installed" $!
    add_metadata "yarn" "$yarn_version"

    if [ "$DISABLE_TELEMETRY" = "true" ]; then
      yarn config set --home enableTelemetry 0
    fi
  fi

  if [ -n "$pnpm_version" ]; then
    corepack prepare pnpm@${pnpm_version} --activate &
    info_spinner "Installing pnpm $pnpm_version" "pnpm $pnpm_version installed" $!
    add_metadata "pnpm" "$pnpm_version"
  fi
fi
