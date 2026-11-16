#!/usr/bin/env bash

set -euo pipefail

# Runs each test-<name> job twice; the warm run must restore test.env's RESTORES_CACHE_DIRECTORIES
# and download nothing unless test.env gives a DOWNLOADS_ON_WARM_RUN reason.

TESTS_DIR="${TESTS_DIR:-repo/test/resources}"
JOB_PREFIX="${JOB_PREFIX:-test-}"
RUNS="${RUNS:-2}"
# Jobs that run at once; each builds its own rootfs, so a small worker wants a low number.
PARALLEL="${PARALLEL:-4}"
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

function require_env() {
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
    [[ -f "$dir/test.sh" ]] && basename "$dir"
  done
}

function output_from_marker() {
  local log="$1"
  if ! grep -qF "$TASK_START_MARKER" "$log"; then
    echo "the task never printed $TASK_START_MARKER (every test task must run test/resources/run.sh)" >&2
    return 1
  fi
  awk -v marker="$TASK_START_MARKER" 'index($0, marker) { seen = 1 } seen' "$log"
}

# Prints a finished build's events, one JSON per line. The stream stays open after `end`, and
# `fly curl` leaves its curl child behind when killed, so run curl itself and kill it there.
function build_events() {
  local build_id="$1" token fd line
  token="$(fly curl /api/v1/info --print-and-exit | sed -n 's/.*bearer \([^"]*\)".*/\1/p')"
  coproc EVENTS { exec curl -fsN -H "Authorization: bearer $token" "$FLY_API_URL/api/v1/builds/$build_id/events"; }
  fd="${EVENTS[0]}"
  while IFS= read -r -u "$fd" line; do
    [[ "$line" == "event: end" ]] && break
    [[ "$line" == "data: "* ]] && echo "${line#data: }"
  done
  kill "$EVENTS_PID" 2> /dev/null || true
}

# The build log doesn't say which step a line came from, and the check and repo get log the same
# line, so read the setup-runtime get steps' own events.
function require_rootfs_cache_hit() {
  local job="$1" log="$2" build_name build_id events get_ids get_id
  build_name="$(sed -n "s|^started $PIPELINE/$job #\([0-9]*\)\$|\1|p" "$log" | tail -1)"
  build_id="$(fly curl "/api/v1/teams/$FLY_TEAM/pipelines/$PIPELINE/jobs/$job/builds/$build_name" 2> /dev/null | jq -r .id)"
  events="$(build_events "$build_id")"
  get_ids="$(fly curl "/api/v1/builds/$build_id/plan" 2> /dev/null |
    jq -r '.. | objects | select(.get.resource? // "" | startswith("setup-runtime-")) | .id')"
  if [[ -z "$get_ids" ]]; then
    echo "$job #$build_name: found no setup-runtime get step in build $build_id's plan"
    return 1
  fi
  for get_id in $get_ids; do
    if ! jq -e --arg id "$get_id" 'select(.event == "log" and .data.origin.id == $id
        and (.data.payload | contains("found existing resource cache")))' <<< "$events" > /dev/null; then
      echo "$job #$build_name rebuilt its rootfs (get $get_id) instead of using the resource cache"
      return 1
    fi
  done
}

# Prints "<steps>|<cache_keys>|<downloads reason>" from a test's test.env (the union of all of them for full).
function read_test_env() {
  local name="$1" test steps="" cache_keys="" downloads_reason=""
  if [[ "$name" == full ]]; then
    for test in $(available_tests); do
      steps+=" $test"
      cache_keys+=" $(source_test_env "$test"; echo "$RESTORES_CACHE_DIRECTORIES")"
    done
    downloads_reason="several tests download on every run by design; the per-test jobs are where a missed cache shows up"
  else
    steps="$name"
    source_test_env "$name"
    cache_keys="$RESTORES_CACHE_DIRECTORIES"
    downloads_reason="$DOWNLOADS_ON_WARM_RUN"
  fi
  echo "$steps|$(tr ' ' '\n' <<< "$cache_keys" | awk 'NF && !seen[$0]++' | xargs)|$downloads_reason"
}

function source_test_env() {
  RESTORES_CACHE_DIRECTORIES=""
  DOWNLOADS_ON_WARM_RUN=""
  # shellcheck source=/dev/null
  [[ -f "$TESTS_DIR/$1/test.env" ]] && source "$TESTS_DIR/$1/test.env"
  return 0
}

function run_test() {
  local name="$1"
  local job="$JOB_PREFIX$name"
  local steps cache_keys downloads_reason
  IFS='|' read -r steps cache_keys downloads_reason <<< "$(read_test_env "$name")"

  echo
  echo "=================================================================="
  echo "  $job"
  echo "=================================================================="

  # Start with a cold task cache; the first run populates it.
  local step
  for step in $steps; do
    if ! fly clear-task-cache -j "$PIPELINE/$job" --step "$step" -n; then
      echo "$job: could not clear the task cache of step $step, so run 1 would not start cold"
      return 1
    fi
  done

  local run log
  for (( run = 1; run <= RUNS; run++ )); do
    log="$WORK_DIR/$name.$run.log"
    echo "--- $job: run $run of $RUNS"
    if ! fly trigger-job -j "$PIPELINE/$job" --watch 2>&1 | tee "$log"; then
      echo "$job failed on run $run of $RUNS"
      return 1
    fi
  done

  require_rootfs_cache_hit "$job" "$log" || return 1

  local output
  output="$(output_from_marker "$log")" || return 1

  if [[ -n "$downloads_reason" ]]; then
    echo "$job: download check skipped: $downloads_reason"
  elif grep -Eq "Download|Pulling" <<< "$output"; then
    echo "$job downloaded on run $RUNS, so its caches were not reused:"
    grep -E "Download|Pulling" <<< "$output" | head -5
    return 1
  fi

  # The download check passes for a run that did nothing, so also require cache events.
  # They are logged before the marker, so search the whole log. The unit (files=, images=) varies.
  local key
  for key in $cache_keys; do
    if ! grep -Eq "\[cache\] restore $key from=local [a-z]+=[1-9]" "$log"; then
      echo "$job did not restore cache $key on run $RUNS"
      return 1
    fi
  done

  echo "PASS: $job"
}

require_env FLY_API_URL
require_env FLY_USERNAME
require_env FLY_PASSWORD
require_env PIPELINE

if [[ ! -d "$TESTS_DIR" ]]; then
  echo "TESTS_DIR '$TESTS_DIR' does not exist - is the repo input mapped?" >&2
  exit 1
fi

declare -a selected=()
if [[ -n "$TESTS" ]]; then
  read -r -a selected <<< "$TESTS"
else
  mapfile -t selected < <(available_tests)
  selected+=( full )
fi

for name in "${selected[@]}"; do
  if [[ "$name" != full && ! -f "$TESTS_DIR/$name/test.sh" ]]; then
    echo "Unknown test '$name'. Available: $(available_tests | xargs) full" >&2
    exit 1
  fi
done

install_fly
fly login -c "$FLY_API_URL" -n "$FLY_TEAM" -u "$FLY_USERNAME" -p "$FLY_PASSWORD"

echo "Running ${#selected[@]} test(s), $RUNS runs each, $PARALLEL at a time: ${selected[*]}"

for name in "${selected[@]}"; do
  while (( $(jobs -rp | wc -l) >= PARALLEL )); do wait -n || true; done
  echo "started $JOB_PREFIX$name"
  {
    if run_test "$name" > "$WORK_DIR/$name.out" 2>&1; then status=PASS; else status=FAIL; fi
    echo "$status" > "$WORK_DIR/$name.status"
    echo "finished $JOB_PREFIX$name: $status"
  } &
done
wait

declare -a failed=()
for name in "${selected[@]}"; do
  cat "$WORK_DIR/$name.out"
  [[ "$(cat "$WORK_DIR/$name.status" 2>/dev/null)" == PASS ]] || failed+=("$name")
done

echo
if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "All tests passed: ${selected[*]}"
