#!/bin/bash

source "$RUNTIME_DIR/docker/docker-functions.sh"
source "$RUNTIME_DIR/docker/docker-cache.sh"

function start_docker_daemon() {
  # Waits DOCKERD_TIMEOUT seconds for startup (default: 60)
  DOCKERD_TIMEOUT="${DOCKERD_TIMEOUT:-60}"
  # Accepts optional DOCKER_OPTS (default: --data-root /scratch/docker)
  DOCKER_OPTS="${DOCKER_OPTS:-}"

  export DOCKER_OPTS

  # Constants
  export DOCKERD_PID_FILE="/tmp/docker.pid"
  export DOCKERD_LOG_FILE="/tmp/docker.log"

  if grep -q cgroup2 /proc/filesystems; then
    cgroups_version='v2'
  else
    cgroups_version='v1'
  fi

  export cgroups_version

  start_docker
  await_docker
  date +%s > /tmp/docker-start
}

function restore_docker_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "$RUNTIME_DIR/docker" ]]; then
    info "Restoring docker images"
    docker_load_cache
  fi
}

register_initialize_callback start_docker_daemon
register_initialize_callback restore_docker_cache
register_teardown_callback teardown_docker
