#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

export SDKMAN_DIR="$chroot_dir$SDKMAN_RUNTIME_DIR"

function sdkman_install() {
  local installer
  installer=$(mktemp)
  curl_retry -s 'https://get.sdkman.io?ci=true&rcupdate=false' -o "$installer"
  local attempt=0
  # The installer's own downloads don't retry, and it refuses to install over a partial install.
  until bash "$installer"; do
    (( attempt++ < ${dependency_download_retries:-0} )) || return 1
    rm -rf "$SDKMAN_DIR"
    sleep 5
  done
  rm -f "$installer"
  echo "export SDKMAN_DIR=$SDKMAN_RUNTIME_DIR; source $SDKMAN_RUNTIME_DIR/bin/sdkman-init.sh" >> "$RUNTIME_BASHRC"
  mkdir -p  "$SDKMAN_DIR/etc"
  echo "sdkman_selfupdate_feature=false" > "$SDKMAN_DIR/etc/config"
  echo "sdkman_auto_answer=true" >> "$SDKMAN_DIR/etc/config"
  echo "sdkman_colour_enable=true" >> "$SDKMAN_DIR/etc/config"
  # sdkman_auto_env doesn't work here, so it is disabled.
  echo "sdkman_auto_env=false" >> "$SDKMAN_DIR/etc/config"
  echo "sdkman_auto_complete=false" >> "$SDKMAN_DIR/etc/config"
  echo "sdkman_checksum_enable=true" >> "$SDKMAN_DIR/etc/config"

  cp "$ROOT_DIR/includes/sdkman.sh" "$chroot_dir/$RUNTIME_DIR/plugins/sdkman.sh"
  cp "$ROOT_DIR/includes/gradle.sh" "$chroot_dir/$RUNTIME_DIR/plugins/gradle.sh"
  cp "$ROOT_DIR/includes/maven.sh" "$chroot_dir/$RUNTIME_DIR/plugins/maven.sh"
}

if runtime_wanted sdkman; then
  sdkman_install &
  info_spinner "Installing sdkman" "Sdkman installed" $!
fi

if [[ "$sdkman_enabled" = "true" ]]; then
  add_task_env_var "SDKMAN_ENABLED=true"
  add_metadata "sdkman" "true"
fi
