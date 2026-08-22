#!/bin/bash

export GRADLE_USER_HOME="$RUNTIME_HOME/.gradle"

function prepare_gradle_config() {
  # Persist gradle.properties at build time
  mkdir -p "$GRADLE_USER_HOME"
  cat <<EOF > "$GRADLE_USER_HOME"/gradle.properties
org.gradle.caching=true
org.gradle.parallel=true
# The configuration cache lives in the project cache dir, which defaults to
# <project>/.gradle - a fresh checkout on every CI build, so it would never be
# reused. Point it at the gradle home this script already archives instead
# ('configuration-cache' is in the tar list below). Set here and not through a
# GRADLE_PROP_ param because only this script knows where the runtime lives.
org.gradle.projectcachedir=$GRADLE_USER_HOME
EOF
  # Overwrite gradle.properties with GRADLE_PROP_ environment variables
  while IFS='=' read -r name value ; do
    if [[ $name == GRADLE_PROP_* ]]; then
      prop_name=$(echo "${name#GRADLE_PROP_}" | tr '_' '.')
      # Remove existing property if it exists
      sed -i "/^${prop_name}=/d" "$GRADLE_USER_HOME"/gradle.properties
      echo "${prop_name}=${value}" >> "$GRADLE_USER_HOME"/gradle.properties
    fi
  done < <(env)
}

function prepare_gradle_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "$GRADLE_USER_HOME" ]]; then
    info "Saving gradle cache..."
    mkdir -p "$CACHE_DIRECTORY/gradle"
    # Only cache what is needed
    # caches/modules-2
    # wrapper/dists
    tar -I lz4 -cf "$CACHE_DIRECTORY/gradle/archive.tar.lz4" \
      -C "$GRADLE_USER_HOME" \
      caches/jars-9 caches/modules-2 wrapper/dists caches/build-cache-1 configuration-cache 2>/dev/null || true
  fi
}

function restore_gradle_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -f "$CACHE_DIRECTORY/gradle/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
    info "Restoring gradle cache..."
    restore_lz4_cache "$CACHE_DIRECTORY/gradle/archive.tar.lz4" "$GRADLE_USER_HOME"
  fi
}

register_initialize_callback prepare_gradle_config
register_initialize_callback restore_gradle_cache
register_teardown_callback prepare_gradle_cache
