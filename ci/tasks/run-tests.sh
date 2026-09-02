#!/usr/bin/env bash

set -euo pipefail

# Drives each test job twice so the second run verifies cache restoration.

TESTS_DIR="${TESTS_DIR:-repo/example/tests}"

# Test jobs are named test-<directory> and use the same task step.
JOB_PREFIX="${JOB_PREFIX:-test-}"
TEST_STEP="${TEST_STEP:-test-image}"

RUNS="${RUNS:-2}"

# Space-separated test names; empty means every directory under TESTS_DIR.
TESTS="${TESTS:-}"

# Task containers have the ATC URL but not BUILD_* metadata.
FLY_API_URL="${FLY_API_URL:-${ATC_EXTERNAL_URL:-}}"
FLY_TEAM="${FLY_TEAM:-main}"
PIPELINE="${PIPELINE:-}"
FLY_USERNAME="${FLY_USERNAME:-}"
FLY_PASSWORD="${FLY_PASSWORD:-}"

# The marker separates task output from the resource get output.
TASK_START_MARKER=">>> TEST TASK START <<<"

WORK_DIR="$(mktemp -d)"
FLY="$WORK_DIR/fly"

function require() {
  local name="$1"
  if [[ -z "${!name}" ]]; then
    echo "$name is required but empty" >&2
    exit 1
  fi
}

# Fetch the Fly CLI from the ATC so its version matches the target.
function install_fly() {
  local arch
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) arch="$(uname -m)" ;;
  esac

  curl -fsSL -o "$FLY" "$FLY_API_URL/api/v1/cli?arch=$arch&platform=linux"
  chmod +x "$FLY"
}

function fly() {
  "$FLY" -t self "$@"
}

function available_tests() {
  local dir
  for dir in "$TESTS_DIR"/*/; do
    [[ -f "$dir/task.yml" ]] && basename "$dir"
  done
}

# Return only output produced by the test task.
function task_output() {
  local log="$1"
  if ! grep -qF "$TASK_START_MARKER" "$log"; then
    echo "the task never printed $TASK_START_MARKER" >&2
    echo "(every test task must source example/tests/assert.sh as its first statement)" >&2
    return 1
  fi
  awk -v marker="$TASK_START_MARKER" 'index($0, marker) { seen = 1 } seen' "$log"
}

# run_test <name>; returns non-zero with a reason on stdout when the test fails.
function run_test() {
  local name="$1"
  local job="$JOB_PREFIX$name"
  local dir="$TESTS_DIR/$name"

  # Reset per-test settings before loading the test configuration.
  local EXPECT_IN_OUTPUT=""
  local FORBID_IN_OUTPUT=""
  local SKIP_CACHE_CHECK="false"
  # shellcheck source=/dev/null
  [[ -f "$dir/test.env" ]] && source "$dir/test.env"

  echo
  echo "=================================================================="
  echo "  $job"
  echo "=================================================================="

  # Start with a cold task cache; the first run populates it.
  fly clear-task-cache -j "$PIPELINE/$job" --step "$TEST_STEP" -n || true

  local run log
  for (( run = 1; run <= RUNS; run++ )); do
    log="$WORK_DIR/$name.$run.log"
    echo "--- $job: run $run of $RUNS"

    # Propagate the watched build's status.
    if ! fly trigger-job -j "$PIPELINE/$job" --watch 2>&1 | tee "$log"; then
      echo "$job failed on run $run of $RUNS"
      return 1
    fi
  done

  local output
  if ! output="$(task_output "$log")"; then
    echo "$job produced no recognisable task output on its last run"
    return 1
  fi

  # Cache events occur before the task marker, so inspect the full log.
  local full_output
  full_output="$(cat "$log")"

  # The second run should not download dependencies.
  if [[ "$SKIP_CACHE_CHECK" != "true" ]] && grep -Eq "Download|Pulling" <<< "$output"; then
    echo "$job downloaded on run $RUNS, so its caches were not reused:"
    grep -E "Download|Pulling" <<< "$output" | head -5
    return 1
  fi

  # Tests can require or forbid specific cache events.
  local pattern
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    if ! grep -Eq "$pattern" <<< "$full_output"; then
      echo "$job did not print /$pattern/ on run $RUNS"
      return 1
    fi
  done <<< "$EXPECT_IN_OUTPUT"

  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    if grep -Eq "$pattern" <<< "$full_output"; then
      echo "$job printed /$pattern/ on run $RUNS, which it must not:"
      grep -E "$pattern" <<< "$full_output" | head -5
      return 1
    fi
  done <<< "$FORBID_IN_OUTPUT"

  echo "PASS: $job"
}

require FLY_API_URL
require FLY_USERNAME
require FLY_PASSWORD
require PIPELINE

if [[ ! -d "$TESTS_DIR" ]]; then
  echo "TESTS_DIR '$TESTS_DIR' does not exist - is the repo input mapped?" >&2
  exit 1
fi

install_fly
fly login -c "$FLY_API_URL" -n "$FLY_TEAM" -u "$FLY_USERNAME" -p "$FLY_PASSWORD"

declare -a selected=()
if [[ -n "$TESTS" ]]; then
  read -r -a selected <<< "$TESTS"
else
  mapfile -t selected < <(available_tests)
fi

echo "Running ${#selected[@]} test(s), $RUNS runs each: ${selected[*]}"

# Run all tests before reporting failures.
declare -a failed=()
for test_name in "${selected[@]}"; do
  run_test "$test_name" || failed+=("$test_name")
done

echo
if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "All tests passed: ${selected[*]}"
