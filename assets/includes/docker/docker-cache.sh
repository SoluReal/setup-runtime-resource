#!/bin/bash

DOCKER_CACHE_DIR="/cache/docker"

function docker_load_cache() {
  if [ -d "$DOCKER_CACHE_DIR" ]; then
    if ls $DOCKER_CACHE_DIR/*.tar.gz >/dev/null 2>&1; then
      for file in $DOCKER_CACHE_DIR/*.tar.gz; do
        docker load < $file
      done
    fi
  fi
}

function docker_save_cache() {
  # Note: this function assumes that images are immutable (once cached, subsequent runs don't change the tagged image)
  local images="$*"

  # Ensure cache directory exists
  if [ ! -d "$DOCKER_CACHE_DIR" ]; then
    mkdir -p "$DOCKER_CACHE_DIR"
  fi

  # Create a temporary directory
  local tmp_cache
  tmp_cache=$(mktemp -d)

  # Move all cached images to the temporary directory
  if [ -d "$DOCKER_CACHE_DIR" ]; then
    mv "$DOCKER_CACHE_DIR"/*.tar.gz "$tmp_cache/" 2>/dev/null || true
  fi

  for image in $images; do
    safe_image="${image//\//-}"
    safe_image="${safe_image//:/_}"
    local cached_file="$tmp_cache/$safe_image.tar.gz"

    if [ -f "$cached_file" ]; then
      # Move back from temp dir to cache dir since that is faster than exporting again
      mv "$cached_file" "$DOCKER_CACHE_DIR"
    else
      # Save the image if not in cache
      docker save "$image" | gzip > "$DOCKER_CACHE_DIR/$safe_image.tar.gz"
    fi
  done

  rm -rf "$tmp_cache"
}

function teardown_docker() {
  set -e
  DOCKER_END_DATE=$(date +%s)

  USED_IMAGES=$(docker events --since $DOCKER_START_DATE --until $DOCKER_END_DATE --format '{{json .}}' \
    | jq -r 'select(.Type=="container") | .Actor.Attributes.image' \
    | sort | uniq | xargs)

  if [[ -n "$USED_IMAGES" ]]; then
    docker_save_cache $USED_IMAGES
  else
    # Cleanup if none of the previously cached images was used.
    # Might not be the desired behaviour in every case but sticking with this for now.
    rm -rf $DOCKER_CACHE_DIR
  fi

  stop_docker
}
