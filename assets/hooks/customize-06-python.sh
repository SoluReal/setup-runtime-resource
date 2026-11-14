#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

# Bump to pick up newer patch releases; a release only lists its latest patch per minor.
PBS_RELEASE=20261110
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/$PBS_RELEASE"

if [[ -n "$python_version" ]]; then
  if ! [[ "$python_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    error "python.version must look like 3.12 or 3.12.2, got '$python_version'"
    exit 1
  fi

  case $(uname -m) in
    x86_64) pbs_arch="x86_64" ;;
    aarch64) pbs_arch="aarch64" ;;
    *) error "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac

  flavor="install_only"
  [[ "$minimal_image" = "true" ]] && flavor="install_only_stripped"

  workdir=$(mktemp -d)

  # SHA256SUMS lists every asset, which resolves 3.12 to its patch version and verifies the download.
  curl_retry -fsSL "$PBS_URL/SHA256SUMS" -o "$workdir/SHA256SUMS"
  pattern="^cpython-${python_version//./\\.}(\\.[0-9]+)?\\+$PBS_RELEASE-$pbs_arch-unknown-linux-gnu-$flavor\\.tar\\.gz$"
  asset=$(awk '{print $2}' "$workdir/SHA256SUMS" | grep -E "$pattern" | sort -V | tail -1 || true)
  if [[ -z "$asset" ]]; then
    error "No CPython $python_version for $pbs_arch in python-build-standalone release $PBS_RELEASE"
    exit 1
  fi
  resolved=${asset#cpython-}
  resolved=${resolved%%+*}

  info "Installing Python $resolved for $pbs_arch"

  (
    curl_retry -fsSL "$PBS_URL/${asset//+/%2B}" -o "$workdir/$asset"
    (cd "$workdir" && grep -F "  $asset" SHA256SUMS | sha256sum -c -)
    mkdir -p "$chroot_dir$PYTHON_RUNTIME_DIR"
    tar -xzf "$workdir/$asset" --strip-components=1 -C "$chroot_dir$PYTHON_RUNTIME_DIR"
  ) &
  info_spinner "Downloading and extracting Python" "Python installed" $!
  rm -rf "$workdir"

  # No EXTERNALLY-MANAGED marker is shipped: the runtime user owns this interpreter, so pip may install into it.
  echo "export PATH=$PYTHON_RUNTIME_DIR/bin:\$PATH" >> "$chroot_dir$RUNTIME_HOME/.bashrc"

  add_metadata "python" "$resolved"
fi
