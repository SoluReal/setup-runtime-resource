#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

if [[ -n "$golang_version" ]]; then
  export GOROOT="$chroot_dir$GOLANG_RUNTIME_DIR"
  mkdir -p "$GOROOT"

  # Detect architecture
  arch=$(uname -m)
  case $arch in
    x86_64) goarch="amd64" ;;
    aarch64) goarch="arm64" ;;
    *) echo "Unsupported architecture: $arch"; exit 1 ;;
  esac

  info "Installing Go $golang_version for $goarch"

  curl -L "https://go.dev/dl/go${golang_version}.linux-${goarch}.tar.gz" | tar -C "$chroot_dir$RUNTIME_DIR" -xz &
  info_spinner "Downloading and extracting Go" "Go installed" $!

  # Go extracts to a directory named 'go', we want it in GOLANG_RUNTIME_DIR
  mv "$chroot_dir$RUNTIME_DIR/go"/* "$GOROOT/"
  rmdir "$chroot_dir$RUNTIME_DIR/go"

  echo "export GOROOT=$GOLANG_RUNTIME_DIR" >> $chroot_dir/root/.bashrc
  echo "export PATH=\$GOROOT/bin:\$PATH" >> $chroot_dir/root/.bashrc
  echo "export GOPATH=/root/go" >> $chroot_dir/root/.bashrc
  echo "export PATH=\$GOPATH/bin:\$PATH" >> $chroot_dir/root/.bashrc

  add_metadata "golang" "$golang_version"
fi
