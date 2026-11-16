#!/bin/bash

if [[ "${TESTCONTAINERS_ROOTLESS:-false}" = "true" ]]; then
  source "$RUNTIME_DIR/docker/podman-functions.sh"
else
  source "$RUNTIME_DIR/docker/docker-functions.sh"
fi
source "$RUNTIME_DIR/docker/docker-cache.sh"
source "$RUNTIME_DIR/docker/docker-login.sh"

export CONTAINER_RUNTIME_PID_FILE="/tmp/container-runtime.pid"
export CONTAINER_RUNTIME_LOG_FILE="/tmp/container-runtime.log"

function start_container_runtime() {
  CONTAINER_RUNTIME_TIMEOUT="${CONTAINER_RUNTIME_TIMEOUT:-60}"
  DOCKER_OPTS="${DOCKER_OPTS:-}"

  export DOCKER_OPTS

  if grep -q cgroup2 /proc/filesystems; then
    cgroups_version='v2'
  else
    cgroups_version='v1'
  fi

  export cgroups_version

  start_docker
  await_docker
}

function restore_docker_images() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  info "Restoring docker images"
  load_cached_images
  # Counted after loading: load_cached_images discards corrupt tars.
  local images
  images="$(find "$DOCKER_CACHE_DIR" -maxdepth 1 -name '*.tar' 2>/dev/null | wc -l | tr -d ' ')"
  if (( images > 0 )); then
    cache_event "restore docker-images from=local images=$images"
  fi
  return 0
}

function initialize_docker() {
  start_container_runtime
  restore_docker_images
}

register_initialize_callback initialize_docker
register_teardown_callback teardown_docker
