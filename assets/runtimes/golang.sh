#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

if runtime_wanted golang; then
  export GOROOT="$chroot_dir$GOLANG_RUNTIME_DIR"
  mkdir -p "$GOROOT"

  arch=$(uname -m)
  case $arch in
    x86_64) goarch="amd64" ;;
    aarch64) goarch="arm64" ;;
    *) echo "Unsupported architecture: $arch"; exit 1 ;;
  esac

  info "Installing Go $golang_version for $goarch"

  (
    archive=$(mktemp)
    curl_retry -fsSL "https://go.dev/dl/go${golang_version}.linux-${goarch}.tar.gz" -o "$archive"
    tar -xzf "$archive" -C "$chroot_dir$RUNTIME_DIR"
    rm -f "$archive"
  ) &
  info_spinner "Downloading and extracting Go" "Go installed" $!

  mv "$chroot_dir$RUNTIME_DIR/go"/* "$GOROOT/"
  rmdir "$chroot_dir$RUNTIME_DIR/go"

  if [[ "$minimal_image" = "true" ]]; then
    # test/ and api/ are Go's own test suite and API checks, unused by go build/test/vet;
    # dropped to shrink the image.
    rm -rf "$GOROOT/test" "$GOROOT/api"
  fi

  echo "export GOROOT=$GOLANG_RUNTIME_DIR" >> "$RUNTIME_BASHRC"
  echo "export PATH=\$GOROOT/bin:\$PATH" >> "$RUNTIME_BASHRC"
  echo "export GOPATH=$RUNTIME_HOME/go" >> "$RUNTIME_BASHRC"
  echo "export PATH=\$GOPATH/bin:\$PATH" >> "$RUNTIME_BASHRC"

  add_metadata "golang" "$golang_version"
fi
