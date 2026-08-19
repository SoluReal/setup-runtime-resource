#!/bin/bash

export DOCKER_CACHE_DIR="$CACHE_DIRECTORY/docker"

function docker_load_cache() {
  if [ -d "$DOCKER_CACHE_DIR" ]; then
    if ls "$DOCKER_CACHE_DIR"/*.tar >/dev/null 2>&1; then
      cores=$(nproc --all)

      printf '%s\n' "$DOCKER_CACHE_DIR"/*.tar | \
        xargs -P "$cores" -I{} sh -c 'docker load < "$1"' _ {}
    fi
  fi
}

function save_image() {
  image=$1
  tmp_cache=$2

  # If no tag is specified, assume :latest
  if [[ "$image" != *:* ]]; then
    image="$image:latest"
  fi

  safe_image="${image//\//-}"
  safe_image="${safe_image//:/_}"
  local cached_file="$tmp_cache/$safe_image.tar"

  if [ -f "$cached_file" ]; then
    # Move back from temp dir to cache dir since that is faster than exporting again
    mv "$cached_file" "$DOCKER_CACHE_DIR"
  else
    info "Saving $image"
    mkdir -p "$DOCKER_CACHE_DIR"
    # Save the image if not in cache
    docker save "$image" > "$DOCKER_CACHE_DIR/$safe_image.tar"
  fi
}

function docker_save_cache() {
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
    mv "$DOCKER_CACHE_DIR"/*.tar "$tmp_cache/" 2>/dev/null || true
  fi

  cores=$(nproc --all)
  export -f save_image
  export -f info
  printf '%s\n' $images | xargs -P "$cores" -I{} bash -c 'save_image "$1" "$2"' _ {} "$tmp_cache"

  rm -rf "$tmp_cache"
}

function teardown_docker() {
  set -e
  DOCKER_END_DATE=$(date +%s)

  # TODO -as- 20260819 remove
  set -x

  local events
  if ! events=$(docker events --since "$(cat /tmp/docker-start)" --until "$DOCKER_END_DATE" --format '{{json .}}' 2>/dev/null); then
    # Without the event log there is no way to tell which images were used.
    # Keep whatever is cached rather than falling through to the cleanup below,
    # which would throw away a perfectly good cache over a transient failure.
    info "Could not read container events; leaving the image cache untouched"
    stop_docker
    return
  fi

  # docker and podman emit different event schemas: docker names the field
  # .Action and nests the image under .Actor.Attributes.image, while podman uses
  # .Status with .Image at the top level. Accept either, otherwise this silently
  # matches nothing on one of the two runtimes and the cleanup below wipes the
  # cache on every run.
  USED_IMAGES=$(printf '%s' "$events" \
    | jq -r 'select(.Type=="container") | select((.Action // .Status) == "start") | (.Actor.Attributes.image // .Image)' \
    | sort | uniq | xargs)


  if [[ -n "$USED_IMAGES" ]]; then
    info "Caching docker images"
    docker_save_cache $USED_IMAGES
  else
    # Cleanup if none of the previously cached images was used.
    # Might not be the desired behaviour in every case but sticking with this for now.
    rm -rf "$DOCKER_CACHE_DIR"
  fi
  
  # TODO -as- 20260819 remove
  set +x

  stop_docker
}
