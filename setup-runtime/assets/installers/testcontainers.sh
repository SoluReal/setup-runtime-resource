#!/bin/bash

function testcontainers_get_dependencies() {
  local config="${1}"
  testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [ "$testcontainers" = "true" ]; then
    echo "podman"
  else
    echo ""
  fi
}

function testcontainers_install() {
  local ctr="${1}"
  local config="${2}"
  testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [[ "$testcontainers" = "true" ]]; then
    # See: https://java.testcontainers.org/supported_docker_environment/
    set_env $ctr "TESTCONTAINERS_RYUK_DISABLED=true"
    set_env $ctr "DOCKER_HOST=/run/podman/podman.sock"
  fi
}
