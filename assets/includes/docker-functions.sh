#!/bin/bash

# Taken from: https://github.com/gardener/cc-utils/blob/master/bin/launch-dockerd.sh

sanitize_cgroups() {
  local cgroup="/sys/fs/cgroup"

  mkdir -p "${cgroup}"
  if ! mountpoint -q "${cgroup}"; then
    if ! mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup "${cgroup}"; then
      echo >&2 "Could not make a tmpfs mount. Did you use --privileged?"
      exit 1
    fi
  fi
  mount -o remount,rw "${cgroup}"

  # Skip AppArmor
  # See: https://github.com/moby/moby/commit/de191e86321f7d3136ff42ff75826b8107399497
  export container=docker

  # Mount /sys/kernel/security
  if [[ -d /sys/kernel/security ]] && ! mountpoint -q /sys/kernel/security; then
    if ! mount -t securityfs none /sys/kernel/security; then
      echo >&2 "Could not mount /sys/kernel/security."
      echo >&2 "AppArmor detection and --privileged mode might break."
    fi
  fi

  sed -e 1d /proc/cgroups | while read sys hierarchy num enabled; do
    if [[ "${enabled}" != "1" ]]; then
      # subsystem disabled; skip
      continue
    fi

    grouping="$(cat /proc/self/cgroup | cut -d: -f2 | grep "\\<${sys}\\>")" || true
    if [[ -z "${grouping}" ]]; then
      # subsystem not mounted anywhere; mount it on its own
      grouping="${sys}"
    fi

    mountpoint="${cgroup}/${grouping}"

    mkdir -p "${mountpoint}"

    # clear out existing mount to make sure new one is read-write
    if mountpoint -q "${mountpoint}"; then
      umount "${mountpoint}"
    fi

    mount -n -t cgroup -o "${grouping}" cgroup "${mountpoint}"

    if [[ "${grouping}" != "${sys}" ]]; then
      if [[ -L "${cgroup}/${sys}" ]]; then
        rm "${cgroup}/${sys}"
      fi

      ln -s "${mountpoint}" "${cgroup}/${sys}"
    fi
  done

  # Initialize systemd cgroup if host isn't using systemd.
  # Workaround for https://github.com/docker/for-linux/issues/219
  if ! [[ -d /sys/fs/cgroup/systemd ]]; then
    mkdir "${cgroup}/systemd"
    mount -t cgroup -o none,name=systemd cgroup "${cgroup}/systemd"
  fi
}

# Setup container environment and start docker daemon in the background.
start_docker() {
  echo >&2 "Setting up Testcontainers environment..."
  mkdir -p /var/log
  mkdir -p /var/run

  if [ "${cgroups_version}" == 'v1' ]; then
    sanitize_cgroups
  fi

  # check for /proc/sys being mounted readonly, as systemd does
  if grep '/proc/sys\s\+\w\+\s\+ro,' /proc/mounts >/dev/null; then
    mount -o remount,rw /proc/sys
  fi

  local docker_opts="${DOCKER_OPTS:-}"

  # Pass through `--garden-mtu` from gardian container
  if [[ "${docker_opts}" != *'--mtu'* ]]; then
    local mtu="$(cat /sys/class/net/$(ip route get 8.8.8.8|awk '{ print $5 }')/mtu)"
    docker_opts+=" --mtu ${mtu}"
  fi

  # Use Concourse's scratch volume to bypass the graph filesystem by default
  if [[ "${docker_opts}" != *'--data-root'* ]] && [[ "${docker_opts}" != *'--graph'* ]]; then
    docker_opts+=' --data-root /scratch/docker'
  fi

  rm -f "${DOCKERD_PID_FILE}"
  touch "${DOCKERD_LOG_FILE}"

  echo >&2 "Starting Docker..."
  dockerd ${docker_opts} &>"${DOCKERD_LOG_FILE}" &
  echo "$!" > "${DOCKERD_PID_FILE}"
}

# Wait for docker daemon to be healthy
# Timeout after DOCKERD_TIMEOUT seconds
await_docker() {
  local timeout="${DOCKERD_TIMEOUT}"
  echo >&2 "Waiting ${timeout} seconds for Docker to be available..."
  local start=${SECONDS}
  timeout=$(( timeout + start ))
  until docker info &>/dev/null; do
    if (( SECONDS >= timeout )); then
      echo >&2 'Timed out trying to connect to docker daemon.'
      if [[ -f "${DOCKERD_LOG_FILE}" ]]; then
        echo >&2 '---DOCKERD LOGS---'
        cat >&2 "${DOCKERD_LOG_FILE}"
      fi
      exit 1
    fi
    if [[ -f "${DOCKERD_PID_FILE}" ]] && ! kill -0 $(cat "${DOCKERD_PID_FILE}"); then
      echo >&2 'Docker daemon failed to start, is the container running in privileged mode?'
      if [[ -f "${DOCKERD_LOG_FILE}" ]]; then
        echo >&2 '---DOCKERD LOGS---'
        cat >&2 "${DOCKERD_LOG_FILE}"
      fi
      exit 1
    fi
    sleep 1
  done
}

# Gracefully stop Docker daemon.
stop_docker() {
  if ! [[ -f "${DOCKERD_PID_FILE}" ]]; then
    return 0
  fi
  local docker_pid="$(cat ${DOCKERD_PID_FILE})"
  if [[ -z "${docker_pid}" ]]; then
    return 0
  fi
  kill -TERM ${docker_pid} || true
  local start=${SECONDS}
  echo >&2 "Waiting for Docker daemon to exit..."
  wait ${docker_pid} || true
  rm -rf $DOCKERD_PID_FILE
}
