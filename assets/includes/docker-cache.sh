#!/bin/bash

DOCKER_CACHE_DIR="/cache/docker"

function docker_load_cache() {
  # Load cached docker images.
  if [ -d "$DOCKER_CACHE_DIR" ]; then
    # Load if tar file
    if ls $DOCKER_CACHE_DIR/*.tar >/dev/null 2>&1; then
      for file in $DOCKER_CACHE_DIR/*.tar; do
        docker load -i "$file"
      done
    fi

    # Load if tar.gz file
    if ls $DOCKER_CACHE_DIR/*.tar.gz >/dev/null 2>&1; then
      for file in $DOCKER_CACHE_DIR/*.tar.gz; do
        gunzip "$file"
        docker load -i "${file/.gz/}"
      done
    fi
  fi
}

function docker_save_cache() {
  # Note: this function assumes that images are immutable (once cached, subsequent runs don't change the tagged image)
  local images="${1}"

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
    local cached_file="$tmp_cache/$image.tar.gz"

    if [ -f "$cached_file" ]; then
      # Move back from temp dir to cache dir
      echo "Restoring cached image: $image"
      mv "$cached_file" "$DOCKER_CACHE_DIR/"
    else
      # Save the image if not in cache
      echo "Saving image: $image"
      docker save "$image" | gzip > "$DOCKER_CACHE_DIR/$image.tar.gz"
    fi
  done

  rm -rf "$tmp_cache"
}

function teardown_docker() {
  echo "Checking which images are used since: $START_TIME"
  END_DATE=$(date +%s)

  echo "docker events: $(docker events --since $START_TIME --until $END_DATE)"

  USED_IMAGES=$(docker events --since $START_TIME --until $END_DATE --format '{{json .}}' \
    | jq -r 'select(.Type=="container") | .Actor.Attributes.image' | sort | uniq)

  echo "images used $USED_IMAGES"
  if [[ -n "$USED_IMAGES" ]]; then
    docker_save_cache $USED_IMAGES
  else
    # Cleanup if none of the previously cached images was used.
    # Might not be the desired behaviour in every case but sticking with this for now.
    rm -rf $DOCKER_CACHE_DIR
  fi

  stop_docker
}
