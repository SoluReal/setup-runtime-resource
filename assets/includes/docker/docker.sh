#!/bin/bash

# Make sure we start the docker daemon only once.
if [ ! -f /tmp/docker_started ]; then
  touch /tmp/docker_started

  source /var/runtimes/docker/docker-cache.sh
  source /var/runtimes/docker/docker-functions.sh

  # Waits DOCKERD_TIMEOUT seconds for startup (default: 60)
  DOCKERD_TIMEOUT="${DOCKERD_TIMEOUT:-60}"
  # Accepts optional DOCKER_OPTS (default: --data-root /scratch/docker)
  DOCKER_OPTS="${DOCKER_OPTS:-}"

  # Constants
  DOCKERD_PID_FILE="/tmp/docker.pid"
  DOCKERD_LOG_FILE="/tmp/docker.log"

  if grep -q cgroup2 /proc/filesystems; then
    cgroups_version='v2'
  else
    cgroups_version='v1'
  fi

  start_docker
  await_docker
  DOCKER_START_DATE=$(date +%s)

  trap teardown_docker EXIT

  docker_load_cache
fi
