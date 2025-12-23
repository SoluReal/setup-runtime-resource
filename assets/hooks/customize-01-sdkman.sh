#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source $ROOT_DIR/common.sh

export SDKMAN_DIR="$chroot_dir$SDKMAN_RUNTIME_DIR"

function sdkman_install() {
  curl -s 'https://get.sdkman.io?ci=true&rcupdate=false' | bash
  echo "export SDKMAN_DIR=$SDKMAN_RUNTIME_DIR; source $SDKMAN_RUNTIME_DIR/bin/sdkman-init.sh" >> $chroot_dir/root/.bashrc
  mkdir -p  "$SDKMAN_DIR/etc"
  echo "sdkman_selfupdate_feature=false" > "$SDKMAN_DIR/etc/config"
  echo "sdkman_auto_answer=true" >> "$SDKMAN_DIR/etc/config"
  echo "sdkman_colour_enable=true" >> "$SDKMAN_DIR/etc/config"
  # Auto_env doesn't seem to work so disabled (for now at least)
  echo "sdkman_auto_env=false" >> "$SDKMAN_DIR/etc/config"
  echo "sdkman_auto_complete=false" >> "$SDKMAN_DIR/etc/config"
  echo "sdkman_checksum_enable=true" >> "$SDKMAN_DIR/etc/config"
}

if [[ -n "$java_version" || "$sdkman_enabled" = "true" ]]; then
  sdkman_install &
  info_spinner "Installing sdkman" "Sdkman installed" $!
fi
