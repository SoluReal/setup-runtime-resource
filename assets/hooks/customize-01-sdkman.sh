#!/bin/bash

set -e

chroot_dir="$1"
source $ROOT_DIR/common.sh

export SDKMAN_DIR="$chroot_dir$SDKMAN_RUNTIME_DIR"

function sdkman_install() {
  curl -s 'https://get.sdkman.io?ci=true&rcupdate=false' | bash
  echo "export SDKMAN_DIR=$SDKMAN_RUNTIME_DIR; source $SDKMAN_RUNTIME_DIR/bin/sdkman-init.sh" >> $chroot_dir/root/.bashrc
}

if [[ -n "$java_version" ]]; then
  sdkman_install &
  info_spinner "Installing sdkman" "Sdkman installed" $!
fi
