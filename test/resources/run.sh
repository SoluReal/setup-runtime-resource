#!/bin/bash
set -e

# ci/tasks/run-tests.sh splits the build log here so its no-download check ignores the rootfs
# build's downloads, which say nothing about the caches.
echo ">>> TEST TASK START <<<"

assert_contains() {
  local needle="$1"
  local input

  input="$(cat)"

  if [[ "$input" != *"$needle"* ]]; then
    echo "Expected '$needle' to be in '$input'"
    exit 1
  fi
}

assert_not_contains() {
  local needle="$1"
  local input

  input="$(cat)"

  if [[ "$input" == *"$needle"* ]]; then
    echo "Expected '$needle' to not be in '$input'"
    exit 1
  fi
}

# BASH_ENV must be unset so bash -c doesn't start saving the cache.
bash -c "echo hi" | assert_not_contains "Saving"

: "${TEST:?TEST must name a directory under test/resources}"
export PROJECTS="$PWD/repo/test/resources/projects"

# Sourced, not executed: the BASH_ENV-loaded runtime (nvm, sdk, caches) lives in this shell.
# shellcheck source=/dev/null
source "repo/test/resources/$TEST/test.sh"
