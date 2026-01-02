#!/bin/bash

function create_m2_dir() {
    mkdir -p /root/.m2
    cat <<EOF > /root/.m2/settings.xml
<settings>
<localRepository>/root/.m2/repository</localRepository>
</settings>
EOF
}

function prepare_maven_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "/root/.m2/repository" ]]; then
    info "Saving maven cache..."
    mkdir -p "$CACHE_DIRECTORY/maven"
    tar -I lz4 -cf "$CACHE_DIRECTORY/maven/archive.tar.lz4" -C /root/.m2 repository
  fi
}

function restore_maven_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -f "$CACHE_DIRECTORY/maven/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
    info "Restoring maven cache..."
    mkdir -p /root/.m2
    tar -I lz4 -xf "$CACHE_DIRECTORY/maven/archive.tar.lz4" -C /root/.m2
  fi
}

register_initialize_callback restore_maven_cache
register_teardown_callback prepare_maven_cache
register_teardown_callback create_m2_dir
