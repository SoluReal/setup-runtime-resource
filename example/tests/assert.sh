#!/bin/bash
# Shared assertion helpers, sourced as the first statement of every test task.
# The `repo` input is mounted by every test and holds the whole repository, both
# in CI and locally, so this file is always at "repo/$PROJECTS_DIR/tests/assert.sh".

# Everything a build prints before this line came from the resource `get` that
# built the runtime, not from the test. ci/tasks/run-tests.sh splits the build log
# here so its "nothing was downloaded on the second run" check sees the task's
# output only - a rootfs rebuild on a fresh worker downloads plenty, and says
# nothing about whether the caches worked.
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
