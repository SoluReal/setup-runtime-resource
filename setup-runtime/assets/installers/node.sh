#!/bin/bash

function node_get_dependencies() {
  local pkg_mgr="${1}"
  local config="${2}"
  nodejs_version=$(jq -r '(.source.nodejs.version // "")' <<< "$config")

  # Only return dependencies if a node version is requested
  if [ -n "$nodejs_version" ]; then
    case "$pkg_mgr" in
      apk)
        echo "curl libstdc++" ;;
      apt)
        echo "curl" ;;
      dnf|yum)
        echo "curl" ;;
      *)
        echo "" ;;
    esac
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

    info "installing nodejs: $nodejs_version..."
    log_on_error buildah run "$ctr" -- bash -lc "\
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE='/root/.bashrc' bash &&
      source /root/.bashrc &&
      nvm install $candidate &&
      npm uninstall -g yarn pnpm || true"
    info "nodejs installed"

    if [[ -n "$yarn_version" || -n "$pnpm_version" ]]; then
      info "installing corepack..."
      log_on_error buildah run "$ctr" -- bash -lc "npm install -g corepack"
      info "corepack installed"
    fi

    if [ -n "$yarn_version" ]; then
      info "installing yarn..."
      log_on_error buildah run "$ctr" -- bash -lc "corepack prepare yarn@${yarn_version} --activate"
      info "yarn installed"
    fi
    if [ -n "$pnpm_version" ]; then
      info "installing pnpm: $pnpm_version..."
      log_on_error buildah run "$ctr" -- bash -lc "corepack prepare pnpm@${pnpm_version} --activate"
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
