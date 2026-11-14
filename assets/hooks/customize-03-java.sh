#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source $ROOT_DIR/common.sh
time_hook "$0"

export SDKMAN_DIR="$chroot_dir$SDKMAN_RUNTIME_DIR"

if [[ -n "$java_version" ]]; then
  source $SDKMAN_DIR/bin/sdkman-init.sh

  echo "$extra_java_versions" | jq -r '.[]' | while read -r version; do
    retry sdk install java $version &
    info_spinner "Installing java, candidate: $version" "java candidate $version installed" $!
    add_metadata "java" "$version"
  done

  if [[ "$java_version" =~ ^[0-9]+$ ]]; then
    install_java="$java_version-tem"
  else
    install_java="$java_version"
  fi
  retry sdk install java $install_java &
  info_spinner "Installing java, candidate: $install_java" "Java candidate $install_java installed" $!
  sdk use java $install_java
  add_metadata "java-default" "$install_java"
fi

if [[ -n "$maven_version" ]]; then
  source $SDKMAN_DIR/bin/sdkman-init.sh
  retry sdk install maven $maven_version &
  info_spinner "Installing maven, candidate: $maven_version" "Maven candidate $maven_version installed" $!
  add_metadata "maven" "$maven_version"
fi

if [[ -n "$gradle_version" ]]; then
  source $SDKMAN_DIR/bin/sdkman-init.sh
  retry sdk install gradle $gradle_version &
  info_spinner "Installing gradle, candidate: $gradle_version" "Gradle candidate $gradle_version installed" $!
  add_metadata "gradle" "$gradle_version"
fi
