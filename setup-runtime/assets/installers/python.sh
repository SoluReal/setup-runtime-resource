#!/bin/bash

# https://github.com/pyenv/pyenv/wiki#suggested-build-environment
apk_deps="build-base libffi-dev openssl-dev bzip2-dev zlib-dev xz-dev readline-dev sqlite-dev tk-dev zstd-dev"
apt_deps="build-essential clang make libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev"
dnf_deps="gcc make patch zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel"

function python_get_dependencies() {
  local pkg_mgr="${1}"
  local config="${2}"
  python_version=$(jq -r '(.source.python.version // "")' <<< "$config")

  # Install pyenv only if python key or version is provided
  if [ -n "$python_version" ]; then
    case "$pkg_mgr" in
      apk)
        echo "curl git $apk_deps" ;;
      apt)
        echo "curl git $apt_deps" ;;
      dnf|yum)
        echo "curl git $dnf_deps" ;;
      *)
        echo "" ;;
    esac
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
    log_on_error buildah run "$ctr" -- bash -lc "
      curl -fsSL https://pyenv.run | bash &&
      echo 'export PATH=\"/root/.pyenv/shims:\$PATH\"' >> ~/.bashrc &&
      export PATH=\"\$HOME/.pyenv/bin:\$PATH\" &&
      pyenv install ${python_version} && pyenv global ${python_version}"
    info "python installed"
  fi
}

function python_cleanup() {
  local pkg_mgr="${1}"
  local config="${2}"
  python_version=$(jq -r '(.source.python.version // "")' <<< "$config")

  # Install pyenv only if python key or version is provided
  if [ -n "$python_version" ]; then
    info "cleaning up after python install"
    case "$pkg_mgr" in
      apk)
        log_on_error buildah run "$ctr" -- bash -lc "apk del $apk_deps" ;;
      apt)
        log_on_error buildah run "$ctr" -- bash -lc "apt purge -y $apt_deps" ;;
      dnf)
        log_on_error buildah run "$ctr" -- bash -lc "dnf remove -y $apt_deps || yum remove -y $apt_deps" ;;
    esac
    info "python cleanup completed"
  fi
}
