#!/bin/bash

set -e

rootdir="$1"

if [ -n "$nodejs_version" ]; then
  if [ "$nodejs_version" = "lts" ]; then
    candidate="--lts"
  else
    candidate="$nodejs_version"
  fi

  export NVM_DIR="$rootdir$NVM_RUNTIME_DIR"
  mkdir -p $NVM_DIR
  # TODO -as- 20251119 renovate
  PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'

  echo "export NVM_DIR=$NVM_RUNTIME_DIR; source \$NVM_DIR/nvm.sh" >> $rootdir/root/.bashrc
  echo "export COREPACK_HOME=$COREPACK_HOME_DIR" >> $rootdir/root/.bashrc

  source $NVM_DIR/nvm.sh

  nvm install $candidate
  npm uninstall -g yarn pnpm || true

  mkdir -p /cache/npm
  echo "export NPM_CONFIG_CACHE=/cache/npm" >> $rootdir/root/.bashrc
  export COREPACK_HOME="$rootdir/$COREPACK_HOME_DIR"
  if [[ -n "$yarn_version" || -n "$pnpm_version" ]]; then
    npm install -g corepack
  fi

  if [ -n "$yarn_version" ]; then
    corepack prepare yarn@${yarn_version} --activate

    if [ "$DISABLE_TELEMETRY" = "true" ]; then
      yarn config set --home enableTelemetry 0
    fi

    mkdir -p /cache/yarn
    echo "export YARN_CACHE_FOLDER=/cache/yarn" >> $rootdir/root/.bashrc
  fi

  if [ -n "$pnpm_version" ]; then
    corepack prepare pnpm@${pnpm_version} --activate

    mkdir -p /cache/pnpm
    echo "export PNPM_STORE_PATH=/cache/pnpm" >> $rootdir/root/.bashrc
  fi
fi
