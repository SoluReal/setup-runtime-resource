#!/bin/bash

source "$RUNTIME_DIR/docker/docker-functions.sh"
source "$RUNTIME_DIR/docker/docker-cache.sh"

# Exported at source time (not inside a callback) so teardown_docker/stop_docker,
# which run in a separate backgrounded callback subshell, can still see these paths.
export DOCKERD_PID_FILE="/tmp/docker.pid"
export DOCKERD_LOG_FILE="/tmp/docker.log"

function start_docker_daemon() {
  # Waits DOCKERD_TIMEOUT seconds for startup (default: 60)
  DOCKERD_TIMEOUT="${DOCKERD_TIMEOUT:-60}"
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
  date +%s > /tmp/docker-start
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
