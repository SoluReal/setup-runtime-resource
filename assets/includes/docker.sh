#!/bin/bash

if [[ "${TESTCONTAINERS_ROOTLESS:-false}" = "true" ]]; then
  source "$RUNTIME_DIR/docker/podman-functions.sh"
else
  source "$RUNTIME_DIR/docker/docker-functions.sh"
fi
source "$RUNTIME_DIR/docker/docker-cache.sh"

export CONTAINER_RUNTIME_PID_FILE="/tmp/container-runtime.pid"
export CONTAINER_RUNTIME_LOG_FILE="/tmp/container-runtime.log"

function start_docker_daemon() {
  # Waits CONTAINER_RUNTIME_TIMEOUT seconds for startup (default: 60).
  CONTAINER_RUNTIME_TIMEOUT="${CONTAINER_RUNTIME_TIMEOUT:-60}"
  # Accepts optional DOCKER_OPTS (default: --data-root /scratch/docker)
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

function restore_docker_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "$RUNTIME_DIR/docker" ]]; then
    info "Restoring docker images"
    docker_load_cache
  fi
}

function initialize_docker() {
  start_docker_daemon
  restore_docker_cache
}

register_initialize_callback initialize_docker
register_teardown_callback teardown_docker
