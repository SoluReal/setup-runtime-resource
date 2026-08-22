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

  (
    archive=$(mktemp)
    curl_retry -fsSL "https://go.dev/dl/go${golang_version}.linux-${goarch}.tar.gz" -o "$archive"
    tar -xzf "$archive" -C "$chroot_dir$RUNTIME_DIR"
    rm -f "$archive"
  ) &
  info_spinner "Downloading and extracting Go" "Go installed" $!

  # Go extracts to a directory named 'go', we want it in GOLANG_RUNTIME_DIR
  mv "$chroot_dir$RUNTIME_DIR/go"/* "$GOROOT/"
  rmdir "$chroot_dir$RUNTIME_DIR/go"

  if [[ "$minimal_image" = "true" ]]; then
    # test/ and api/ are Go's own compiler test suite and API-compatibility
    # checks - not used by `go build`/`go test`/`go vet` on user code, so drop
    # them to shrink the image.
    rm -rf "$GOROOT/test" "$GOROOT/api"
  fi

  echo "export GOROOT=$GOLANG_RUNTIME_DIR" >> $chroot_dir$RUNTIME_HOME/.bashrc
  echo "export PATH=\$GOROOT/bin:\$PATH" >> $chroot_dir$RUNTIME_HOME/.bashrc
  echo "export GOPATH=$RUNTIME_HOME/go" >> $chroot_dir$RUNTIME_HOME/.bashrc
  echo "export PATH=\$GOPATH/bin:\$PATH" >> $chroot_dir$RUNTIME_HOME/.bashrc

  add_metadata "golang" "$golang_version"
fi
