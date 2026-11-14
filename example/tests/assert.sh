#!/bin/bash

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
