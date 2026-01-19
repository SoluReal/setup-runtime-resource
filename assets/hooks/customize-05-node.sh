#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

if [ -n "$nodejs_version" ]; then
  if [ "$nodejs_version" = "lts" ]; then
    candidate="--lts"
  else
    candidate="$nodejs_version"
  fi

  export NVM_DIR="$chroot_dir$NVM_RUNTIME_DIR"
  source "$NVM_DIR/nvm.sh"

  nvm install "$candidate"
  add_metadata "node" "$(nvm current)"
  npm uninstall -g yarn pnpm || true

  export COREPACK_HOME="$chroot_dir/$COREPACK_HOME_DIR"
  if [[ -n "$yarn_version" || -n "$pnpm_version" ]]; then
    # Starting with nodejs 25 corepack is no longer bundled with nodejs.
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

  if [ -n "$bun_version" ]; then
    if [ "$bun_version" = "latest" ]; then
        curl -fsSL https://bun.sh/install | BUN_INSTALL="$chroot_dir/usr/local" bash &
    else
        curl -fsSL https://bun.sh/install | BUN_INSTALL="$chroot_dir/usr/local" bash -s -- "bun-v${bun_version}" &
    fi
    info_spinner "Installing bun $bun_version" "bun $bun_version installed" $!
    add_metadata "bun" "$bun_version"
  fi
fi
