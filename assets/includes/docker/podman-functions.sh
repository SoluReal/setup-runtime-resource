#!/bin/bash

# Rootless equivalent of docker-functions.sh. This uses podman instead
# since podman can run rootless and is daemonless.

export XDG_RUNTIME_DIR="$HOME/.run"
PODMAN_SOCKET="${XDG_RUNTIME_DIR}/podman/podman.sock"
PODMAN_SOCKET_DIR="$(dirname "$PODMAN_SOCKET")"
export DOCKER_HOST="unix://${PODMAN_SOCKET}"

# Testcontainers' Ryuk reaper doesn't work against rootless podman.
# Source: https://podman-desktop.io/tutorial/testcontainers-with-podman
export TESTCONTAINERS_RYUK_DISABLED="${TESTCONTAINERS_RYUK_DISABLED:-true}"

# Podman is daemonless, but Testcontainers talks to the API socket, so the
# service has to be started explicitly.
start_docker() {
  info "Setting up rootless Testcontainers environment (podman)..."

  # pasta needs /dev/net/tun for published ports. No image ships it and mknod
  # needs root, so the worker must provide it. Not fatal - podman still runs.
  if [[ ! -e /dev/net/tun ]]; then
    error "/dev/net/tun is missing - rootless container networking (published ports) will not work."
    error "The worker must provide this device (see README: worker requirements)."
  fi

  # podman doesn't create the socket's parent dir; it just fails the bind.
  mkdir -p "$PODMAN_SOCKET_DIR"

  rm -f "${CONTAINER_RUNTIME_PID_FILE}"
  touch "${CONTAINER_RUNTIME_LOG_FILE}"

  info "Starting rootless podman..."
  podman system service --time=0 "$DOCKER_HOST" &>"${CONTAINER_RUNTIME_LOG_FILE}" &
  echo "$!" > "${CONTAINER_RUNTIME_PID_FILE}"
}

# Wait for the rootless podman socket to be healthy.
# Timeout after CONTAINER_RUNTIME_TIMEOUT seconds
await_docker() {
  local timeout="${CONTAINER_RUNTIME_TIMEOUT}"
  info "Waiting ${timeout} seconds for rootless podman socket to be available..."
  local start=${SECONDS}
  timeout=$(( timeout + start ))
  # `podman info` is not a real check: the CLI works without the socket, so it
  # passes even when the service never started. Probe the socket itself.
  until curl -sf --unix-socket "$PODMAN_SOCKET" http://localhost/_ping &>/dev/null; do
    if (( SECONDS >= timeout )); then
      error 'Timed out trying to connect to rootless podman.'
      if [[ -f "${CONTAINER_RUNTIME_LOG_FILE}" ]]; then
        error '---PODMAN LOGS---'
        cat >&2 "${CONTAINER_RUNTIME_LOG_FILE}"
      fi
      exit 1
    fi
    if [[ -f "${CONTAINER_RUNTIME_PID_FILE}" ]] && ! kill -0 $(cat "${CONTAINER_RUNTIME_PID_FILE}") 2>/dev/null; then
      error 'Rootless podman failed to start.'
      if [[ -f "${CONTAINER_RUNTIME_LOG_FILE}" ]]; then
        error '---PODMAN LOGS---'
        cat >&2 "${CONTAINER_RUNTIME_LOG_FILE}"
      fi
      exit 1
    fi
    sleep 0.1
  done
}

# Print this build's container events, one JSON object per line.
#
# --since 0 reads the log from the start rather than from a recorded timestamp.
# That is not "everything ever": the log lives in the task container's own
# $XDG_RUNTIME_DIR/libpod/tmp/events/events.log, which is created fresh for
# every build, so its whole contents are this build's events.
#
# Deliberately no --until. On podman 5.4.2 an --until that has already passed
# ends the read immediately and returns a nondeterministic prefix of the log -
# measured on one worker: 0 events, then 1, then 3, where the same call without
# it returns all 13. Exit status is 0 either way, so it fails silently.
# --stream=false is what terminates the read instead, and it is podman-only,
# which is why this lives here and not in docker-cache.sh.
container_events() {
  podman events --since 0 --stream=false --format '{{json .}}'
}

# Gracefully stop the rootless podman API service.
stop_docker() {
  if [[ -f "${CONTAINER_RUNTIME_PID_FILE}" ]]; then
    local docker_pid="$(cat ${CONTAINER_RUNTIME_PID_FILE})"
    if [[ -n "${docker_pid}" ]]; then
      kill -TERM ${docker_pid} 2>/dev/null || true
      local start=${SECONDS}
      local stop_timeout=$(( start + 30 ))
      info "Waiting for rootless podman to exit..."
      while kill -0 "${docker_pid}" 2>/dev/null; do
        if (( SECONDS >= stop_timeout )); then
          break
        fi
        sleep 0.1
      done
    fi
    rm -f "${CONTAINER_RUNTIME_PID_FILE}"
  fi
}
