#!/bin/bash

function prepare_gradle_config() {
  # Persist gradle.properties at build time
  mkdir -p /root/.gradle
  cat <<EOF > /root/.gradle/gradle.properties
org.gradle.caching=true
org.gradle.parallel=true
EOF
  # Overwrite gradle.properties with GRADLE_PROP_ environment variables
  while IFS='=' read -r name value ; do
    if [[ $name == GRADLE_PROP_* ]]; then
      prop_name=$(echo "${name#GRADLE_PROP_}" | tr '_' '.')
      # Remove existing property if it exists
      sed -i "/^${prop_name}=/d" /root/.gradle/gradle.properties
      echo "${prop_name}=${value}" >> /root/.gradle/gradle.properties
    fi
  done < <(env)
}

function prepare_gradle_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "/root/.gradle" ]]; then
    info "Saving gradle cache..."
    mkdir -p "$CACHE_DIRECTORY/gradle"
    # Only cache what is needed
    # caches/modules-2
    # wrapper/dists
    tar -I lz4 -cf "$CACHE_DIRECTORY/gradle/archive.tar.lz4" \
      -C /root/.gradle \
      --transform='s,^caches/modules-2,caches/modules-2,' \
      --transform='s,^caches/build-cache-1,caches/build-cache-1,' \
      --transform='s,^caches/jars-9,caches/jars-9,' \
      --transform='s,^wrapper/dists,wrapper/dists,' \
      --transform='s,^configuration-cache,configuration-cache,' \
      caches/jars-9 caches/modules-2 wrapper/dists caches/build-cache-1 configuration-cache 2>/dev/null || true
  fi
}

function restore_gradle_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -f "$CACHE_DIRECTORY/gradle/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
    info "Restoring gradle cache..."
    mkdir -p /root/.gradle
    tar -I lz4 -xf "$CACHE_DIRECTORY/gradle/archive.tar.lz4" -C /root/.gradle
  fi
}

register_initialize_callback prepare_gradle_config
register_initialize_callback restore_gradle_cache
register_teardown_callback prepare_gradle_cache
