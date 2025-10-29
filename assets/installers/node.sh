#!/bin/bash

function node_get_dependencies() {
  local config="${1}"
  nodejs_version=$(jq -r '(.source.nodejs.version // "")' <<< "$config")

  # Only return dependencies if a node version is requested
  if [ -n "$nodejs_version" ]; then
    echo "curl"
  else
    echo ""
  fi
}

function node_install() {
  local ctr="${1}"
  local config="${2}"
  nodejs_version=$(jq -r '(.source.nodejs.version // "")' <<< "$config")
  yarn_version=$(jq -r '(.source.nodejs.yarn.version // "")' <<< "$config")
  pnpm_version=$(jq -r '(.source.nodejs.pnpm.version // "")' <<< "$config")

  if [ -n "$nodejs_version" ]; then
    if [ "$nodejs_version" = "lts" ]; then
        candidate="--lts"
      else
        candidate="$nodejs_version"
      fi

    add_metadata "nodejs" "$nodejs_version"
    info "installing nodejs: $nodejs_version..."
    log_on_error buildah run "$ctr" -- bash -lc "\
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE='/root/.bashrc' bash &&
      source /root/.bashrc &&
      nvm install $candidate &&
      npm uninstall -g yarn pnpm || true"
    set_env "$ctr" "NPM_CONFIG_CACHE=/cache/npm && mkdir -p /cache/npm"
    info "nodejs installed"

    if [[ -n "$yarn_version" || -n "$pnpm_version" ]]; then
      info "installing corepack..."
      log_on_error buildah run "$ctr" -- bash -lc "npm install -g corepack"
      info "corepack installed"
    fi

    if [ -n "$yarn_version" ]; then
      info "installing yarn..."
      log_on_error buildah run "$ctr" -- bash -lc "corepack prepare yarn@${yarn_version} --activate"
      set_env "$ctr" "YARN_CACHE_FOLDER=/cache/yarn && mkdir -p /cache/yarn"
      add_metadata "yarn" "$yarn_version"

      if [ "$DISABLE_TELEMETRY" = "true" ]; then
        log_on_error buildah run "$ctr" -- bash -lc "yarn config set --home enableTelemetry 0"
      fi

      info "yarn installed"
    fi
    if [ -n "$pnpm_version" ]; then
      info "installing pnpm: $pnpm_version..."
      log_on_error buildah run "$ctr" -- bash -lc "corepack prepare pnpm@${pnpm_version} --activate"
      set_env "$ctr" "PNPM_STORE_PATH=/cache/pnpm && mkdir -p /cache/pnpm"
      add_metadata "pnpm" "$pnpm_version"

      info "pnpm installed"
    fi
  fi
}

function node_cleanup() {
  local ctr="${1}"
  local config="${2}"
  nodejs_version=$(jq -r '(.source.nodejs.version // "")' <<< "$config")

  if [ -n "$nodejs_version" ]; then
    log_on_error buildah run "$ctr" -- bash -lc "nvm cache clear;"
  fi
}
