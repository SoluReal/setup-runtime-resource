#!/bin/bash

# Rootless equivalent of docker-functions.sh: runs podman's Docker-compatible
# API as a real non-root user, so the container runtime itself never holds
# actual root - even though the outer Concourse task still needs
# `privileged: true` (containerd's non-privileged tasks block user namespace
# creation and don't expose /dev/fuse at all, so there is no way to avoid
# `privileged: true` itself; this only reduces what runs as real root inside
# it). See README for the AppArmor sysctl tradeoff this depends on.

export XDG_RUNTIME_DIR="/run/user/$(id -u "$RUNTIME_USER")"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"

USERNS_SYSCTL="/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
# start_docker and stop_docker run in separate backgrounded callback subshells
# (see docker.sh), so the original value has to survive on disk, not in a
# bash variable.
USERNS_SYSCTL_ORIGINAL_FILE="/tmp/userns-sysctl-original"

# Route every `docker` call (ours and the user's build scripts) through the
# rootless user, so caching and manual `docker build`/`run` calls all land in
# the same podman storage as the daemon started in start_docker.
docker() {
  runuser -u "$RUNTIME_USER" -- env "DOCKER_HOST=$DOCKER_HOST" "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" docker "$@"
}
export -f docker

relax_userns_restriction() {
  if [[ -f "$USERNS_SYSCTL" ]]; then
    local original
    original="$(cat "$USERNS_SYSCTL")"
    echo "$original" > "$USERNS_SYSCTL_ORIGINAL_FILE"
    if [[ "$original" != "0" ]]; then
      if ! echo 0 > "$USERNS_SYSCTL" 2>/dev/null; then
        echo >&2 "Warning: could not relax $USERNS_SYSCTL - rootless podman may fail to start."
      fi
    fi
  fi
}

restore_userns_restriction() {
  if [[ -f "$USERNS_SYSCTL_ORIGINAL_FILE" && -f "$USERNS_SYSCTL" ]]; then
    cat "$USERNS_SYSCTL_ORIGINAL_FILE" > "$USERNS_SYSCTL" 2>/dev/null || true
    rm -f "$USERNS_SYSCTL_ORIGINAL_FILE"
  fi
}

# Setup container environment and start the rootless podman API socket in the background.
start_docker() {
  echo >&2 "Setting up rootless Testcontainers environment (podman)..."

  relax_userns_restriction

  # pasta/slirp4netns (rootless networking) need /dev/net/tun, which most
  # container images don't ship by default.
  if [[ ! -e /dev/net/tun ]]; then
    mkdir -p /dev/net
    mknod -m 666 /dev/net/tun c 10 200
  fi

  mkdir -p "$XDG_RUNTIME_DIR"
  chown "$RUNTIME_USER:$RUNTIME_USER" "$XDG_RUNTIME_DIR"
  chmod 0700 "$XDG_RUNTIME_DIR"

  # Mirror docker-functions.sh's use of Concourse's scratch volume for storage.
  local storage_root="/scratch/podman"
  mkdir -p "$storage_root"
  chown -R "$RUNTIME_USER:$RUNTIME_USER" "$storage_root"

  rm -f "${DOCKERD_PID_FILE}"
  touch "${DOCKERD_LOG_FILE}"

  echo >&2 "Starting rootless podman..."
  runuser -u "$RUNTIME_USER" -- env "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
    podman --root "$storage_root/storage" --runroot "$storage_root/run" \
    system service --time=0 "$DOCKER_HOST" &>"${DOCKERD_LOG_FILE}" &
  echo "$!" > "${DOCKERD_PID_FILE}"
}

# Wait for the rootless podman socket to be healthy.
# Timeout after DOCKERD_TIMEOUT seconds
await_docker() {
  local timeout="${DOCKERD_TIMEOUT}"
  echo >&2 "Waiting ${timeout} seconds for rootless podman to be available..."
  local start=${SECONDS}
  timeout=$(( timeout + start ))
  until runuser -u "$RUNTIME_USER" -- env "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" "DOCKER_HOST=$DOCKER_HOST" podman info &>/dev/null; do
    if (( SECONDS >= timeout )); then
      echo >&2 'Timed out trying to connect to rootless podman.'
      if [[ -f "${DOCKERD_LOG_FILE}" ]]; then
        echo >&2 '---PODMAN LOGS---'
        cat >&2 "${DOCKERD_LOG_FILE}"
      fi
      exit 1
    fi
    if [[ -f "${DOCKERD_PID_FILE}" ]] && ! kill -0 $(cat "${DOCKERD_PID_FILE}") 2>/dev/null; then
      echo >&2 'Rootless podman failed to start.'
      if [[ -f "${DOCKERD_LOG_FILE}" ]]; then
        echo >&2 '---PODMAN LOGS---'
        cat >&2 "${DOCKERD_LOG_FILE}"
      fi
      exit 1
    fi
    sleep 0.1
  done
}

# Gracefully stop the rootless podman service and undo the AppArmor relaxation.
stop_docker() {
  if [[ -f "${DOCKERD_PID_FILE}" ]]; then
    local docker_pid="$(cat ${DOCKERD_PID_FILE})"
    if [[ -n "${docker_pid}" ]]; then
      kill -TERM ${docker_pid} 2>/dev/null || true
      local start=${SECONDS}
      local stop_timeout=$(( start + 30 ))
      echo >&2 "Waiting for rootless podman to exit..."
      while kill -0 "${docker_pid}" 2>/dev/null; do
        if (( SECONDS >= stop_timeout )); then
          break
        fi
        sleep 0.1
      done
    fi
    rm -f "${DOCKERD_PID_FILE}"
  fi

  restore_userns_restriction
}
