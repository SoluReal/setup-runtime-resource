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

# Cache filename for an image reference, e.g.
# docker.io/library/redis:7-alpine -> docker.io-library-redis_7-alpine.tar
function docker_cache_filename() {
  local image="$1"

  # If no tag is specified, assume :latest
  if [[ "$image" != *:* ]]; then
    image="$image:latest"
  fi

  local safe_image="${image//\//-}"
  safe_image="${safe_image//:/_}"
  echo "$safe_image.tar"
}

# Save one image to the cache, but only if it isn't already there.
function save_image_if_missing() {
  local image="$1"
  local cached_file="$DOCKER_CACHE_DIR/$(docker_cache_filename "$image")"

  if [ -f "$cached_file" ]; then
    return 0
  fi

  info "Saving $image"
  docker save "$image" > "$cached_file"
}

function docker_save_cache() {
  local images="$*"

  mkdir -p "$DOCKER_CACHE_DIR"

  # Which cache filenames this run's images map to, so leftover entries from
  # a previous run that weren't used this time can be told apart from ones
  # still in use.
  local -A wanted=()
  local image
  for image in $images; do
    wanted["$(docker_cache_filename "$image")"]=1
  done

  # Drop cache entries for images that weren't used this run - keeping them
  # around would just grow the cache.
  local cached_file base
  for cached_file in "$DOCKER_CACHE_DIR"/*.tar; do
    [[ -e "$cached_file" ]] || continue
    base="$(basename "$cached_file")"
    [[ -n "${wanted[$base]:-}" ]] || rm -f "$cached_file"
  done

  # Save whichever used images aren't already cached, in parallel. Each save
  # runs via `env -u BASH_ENV` rather than a plain `bash -c`: BASH_ENV makes
  # every new bash process re-source bashrc.sh, which would recompute
  # CACHE_DIRECTORY (and so DOCKER_CACHE_DIR) from *this* process's cwd -
  # wrong here, since by teardown time the task script has usually cd'd into
  # a project checkout. Stripping BASH_ENV skips that re-source entirely, so
  # the already-correct inherited values are used as-is.
  local cores
  cores=$(nproc --all)
  export -f save_image_if_missing
  export -f docker_cache_filename
  export -f info
  printf '%s\n' $images | xargs -P "$cores" -I{} env -u BASH_ENV bash -c 'save_image_if_missing "$1"' _ {}
}

function teardown_docker() {
  set -e

  local events events_err
  events_err=$(mktemp)

  # container_events is runtime-specific (see docker-functions.sh and
  # podman-functions.sh); the two runtimes need different flags to produce a
  # bounded, non-streaming result.
  #
  # Never discard stderr here: the runtime reports why it produced no events on
  # that channel, and swallowing it turns a diagnosable failure into a silent one.
  if ! events=$(container_events 2>"$events_err"); then
    # Without the event log there is no way to tell which images were used.
    # Keep whatever is cached rather than falling through to the cleanup below,
    # which would throw away a perfectly good cache over a transient failure.
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

  # docker and podman emit different event schemas: docker names the field
  # .Action and nests the image under .Actor.Attributes.image, while podman uses
  # .Status with .Image at the top level. Accept either, otherwise this silently
  # matches nothing on one of the two runtimes and nothing is ever cached.
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

  stop_docker
}
