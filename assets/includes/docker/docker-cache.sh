#!/bin/bash

export DOCKER_CACHE_DIR="$CACHE_DIRECTORY/docker"

function load_cached_images() {
  if [ -d "$DOCKER_CACHE_DIR" ]; then
    if ls "$DOCKER_CACHE_DIR"/*.tar >/dev/null 2>&1; then
      local cores
      cores=$(nproc --all)

      export -f load_cached_image
      export -f error
      printf '%s\n' "$DOCKER_CACHE_DIR"/*.tar | \
        xargs -P "$cores" -I{} env -u BASH_ENV bash -c 'load_cached_image "$1"' _ {}
    fi
  fi
}

function load_cached_image() {
  local cached_file="$1"

  if ! docker load < "$cached_file" >/dev/null; then
    error "Cached image $(basename "$cached_file") is corrupt, discarding it"
    rm -f "$cached_file"
  fi
}

function image_cache_filename() {
  local image="$1"

  if [[ "$image" != *:* ]]; then
    image="$image:latest"
  fi

  local safe_image="${image//\//-}"
  safe_image="${safe_image//:/_}"
  echo "$safe_image.tar"
}

function save_image_if_missing() {
  local image="$1"
  local cached_file="$DOCKER_CACHE_DIR/$(image_cache_filename "$image")"

  if [ -f "$cached_file" ]; then
    return 0
  fi

  info "Saving $image"

  # Save to a temp file, rename on success: a build cancelled mid-save leaves no corrupt tar.
  local tmp_file="$cached_file.tmp"
  if docker save "$image" > "$tmp_file"; then
    mv "$tmp_file" "$cached_file"
  else
    rm -f "$tmp_file"
  fi
}

function sync_cached_images() {
  local images="$*"

  mkdir -p "$DOCKER_CACHE_DIR"

  rm -f "$DOCKER_CACHE_DIR"/*.tmp

  local -A wanted=()
  local image
  for image in $images; do
    wanted["$(image_cache_filename "$image")"]=1
  done

  local cached_file base
  for cached_file in "$DOCKER_CACHE_DIR"/*.tar; do
    [[ -e "$cached_file" ]] || continue
    base="$(basename "$cached_file")"
    [[ -n "${wanted[$base]:-}" ]] || rm -f "$cached_file"
  done

  # env -u BASH_ENV: a new bash would re-source bashrc.sh and recompute CACHE_DIRECTORY from this
  # cwd, which is wrong once the task script has cd'd into a project checkout.
  local cores
  cores=$(nproc --all)
  export -f save_image_if_missing
  export -f image_cache_filename
  export -f info
  printf '%s\n' $images | xargs -P "$cores" -I{} env -u BASH_ENV bash -c 'save_image_if_missing "$1"' _ {}
}

function teardown_docker() {
  set -e

  local events events_err used_images
  events_err=$(mktemp)

  # Never discard stderr: the runtime reports there why it produced no events.
  if ! events=$(container_events 2>"$events_err"); then
    # Without the event log, keep the cache rather than clean it up over a transient failure.
    info "Could not read container events; leaving the image cache untouched"
    cat "$events_err" >&2
    rm -f "$events_err"
    stop_docker
    return
  fi

  if [[ -s "$events_err" ]]; then
    info "reading container events reported: $(cat "$events_err")"
  fi
  rm -f "$events_err"

  # docker names the field .Action / .Actor.Attributes.image, podman .Status / .Image;
  # accept either, or nothing is ever cached on one of the runtimes.
  used_images=$(printf '%s' "$events" \
    | jq -r 'select(.Type=="container") | select((.Action // .Status) == "start") | (.Actor.Attributes.image // .Image)' \
    | sort | uniq | xargs)

  if [[ -n "$used_images" ]]; then
    info "Caching docker images"
    sync_cached_images $used_images
  else
    rm -rf "$DOCKER_CACHE_DIR"
  fi

  stop_docker
}
