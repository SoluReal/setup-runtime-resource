#!/bin/bash

# Logs in to zero or more registries using numbered task params:
# DOCKER_LOGIN_1_REGISTRY / DOCKER_LOGIN_1_USERNAME / DOCKER_LOGIN_1_PASSWORD,
# DOCKER_LOGIN_2_REGISTRY / ... and so on, stopping at the first missing index.
# Works for both dockerd and the rootless podman-docker shim, since both
# implement `docker login`.
function login_docker_registries() {
  local i=1
  local registry_var username_var password_var registry username

  while true; do
    registry_var="DOCKER_LOGIN_${i}_REGISTRY"
    username_var="DOCKER_LOGIN_${i}_USERNAME"
    password_var="DOCKER_LOGIN_${i}_PASSWORD"
    registry="${!registry_var:-}"

    [[ -n "$registry" ]] || break

    username="${!username_var:-}"

    info "Logging in to ${registry}..."
    if ! echo "${!password_var:-}" | docker login "$registry" --username "$username" --password-stdin; then
      error "Failed to log in to ${registry}"
      return 1
    fi

    i=$((i + 1))
  done
}

register_initialize_callback login_docker_registries
