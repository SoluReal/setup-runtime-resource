#!/bin/bash

# https://github.com/pyenv/pyenv/wiki#suggested-build-environment
apt_deps="build-essential clang make libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev"

function python_get_dependencies() {
  local config="${1}"
  python_version=$(jq -r '(.source.python.version // "")' <<< "$config")

  # Install pyenv only if python key or version is provided
  if [ -n "$python_version" ]; then
    echo "ca-certificates curl git $apt_deps"
  else
    echo ""
  fi
}

function python_install() {
  local ctr="${1}"
  local config="${2}"
  python_version=$(jq -r '(.source.python.version // "")' <<< "$config")

  if [ -n "$python_version" ]; then
    info "installing python: $python_version"
    log_on_error chroot_exec "$ctr" "
      curl -fsSL https://pyenv.run | bash &&
      echo 'export PATH=\"/root/.pyenv/shims:\$PATH\"' >> ~/.bashrc &&
      export PATH=\"\$HOME/.pyenv/bin:\$PATH\" &&
      pyenv install ${python_version} && pyenv global ${python_version}"
    info "python installed"
    add_metadata "python" "$python_version"
  fi
}

function python_cleanup() {
  local ctr="${1}"
  local config="${2}"
  python_version=$(jq -r '(.source.python.version // "")' <<< "$config")

  # Install pyenv only if python key or version is provided
  if [ -n "$python_version" ]; then
    info "cleaning up after python install"
    log_on_error chroot_exec "$ctr" "apt purge -y $apt_deps"
    info "python cleanup completed"
  fi
}
