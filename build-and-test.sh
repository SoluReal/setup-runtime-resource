#!/bin/bash

set -euo pipefail

# Builds the resource image and runs the example tests against a local Concourse
# stack (docker-compose.yml).
#
#   ./build-and-test.sh                 # every test
#   TEST=maven ./build-and-test.sh      # one test
#   TEST="maven gradle" ./build-and-test.sh
#
# Each test is a directory under example/tests/ holding a source.yml (the
# resource `source`), a task.yml (the task config) and an optional test.env with
# per-test knobs. This script only deploys the pipeline and starts its `test`
# job; that job runs ci/tasks/run-tests.sh, which is the same script CI runs, so
# a test passing here is a test passing there.

TESTS_DIR="example/tests"
PIPELINE="${PIPELINE:-setup-runtime}"

# Empty runs every test.
TEST="${TEST:-}"

# full|fuse-only|ignore - what `privileged: true` tasks get on the local worker.
# e.g. CONCOURSE_CONTAINERD_PRIVILEGED_MODE=fuse-only ./build-and-test.sh
export CONCOURSE_CONTAINERD_PRIVILEGED_MODE="${CONCOURSE_CONTAINERD_PRIVILEGED_MODE:-full}"

available_tests() {
  local dir
  for dir in "$TESTS_DIR"/*/; do
    [[ -f "$dir/source.yml" && -f "$dir/task.yml" ]] && basename "$dir"
  done
}

for name in $TEST; do
  if [[ ! -f "$TESTS_DIR/$name/task.yml" ]]; then
    echo "Unknown test '$name'. Available:" >&2
    available_tests | sed 's/^/  /' >&2
    exit 1
  fi
done

echo "Running setup-runtime tests: ${TEST:-all}"

docker-compose -p concource-resource -f docker-compose.yml build git-server
docker-compose -p concource-resource -f docker-compose.yml up -d
# The git-server builds its repository from the mounted working tree when the
# container starts, so without this a test would run against whatever the tree
# looked like the last time the stack came up.
docker-compose -p concource-resource -f docker-compose.yml up -d --force-recreate git-server

HASH="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8; echo)"

docker buildx build \
  -t localhost:5000/setup-runtime-resource:latest \
  -t localhost:5000/setup-runtime-resource:$HASH \
  --progress=plain \
  --push .

until fly -t test login -c http://localhost:8080 -u test -p test
do
  sleep 5
done

# One var per test, holding that test's source.yml verbatim - the same thing the
# deploying pipeline does for ci/pipeline.yml, so both pipelines read the same
# files. The two rewrites below exist only because this stack differs from the
# cluster CI runs on.
source_vars=()
for dir in "$TESTS_DIR"/*/; do
  name="$(basename "$dir")"
  [[ -f "$dir/source.yml" ]] || continue

  # Reset per test so one test's knobs cannot leak into the next.
  FORCE_ROOTLESS=""
  # shellcheck source=/dev/null
  [[ -f "$dir/test.env" ]] && source "$dir/test.env"

  source_yaml="$(cat "$dir/source.yml")"

  # Use dockerd locally unless the test opts into rootless Podman.
  if [[ -n "$FORCE_ROOTLESS" ]]; then
    source_yaml="$(sed "s/^\([[:space:]]*\)rootless:.*/\1rootless: $FORCE_ROOTLESS/" <<< "$source_yaml")"
  fi

  # The local stack is the only one with apt-cacher.
  var_name="SOURCE_$(echo "$name" | tr 'a-z-' 'A-Z_')"
  source_vars+=( --yaml-var "$var_name=$source_yaml
debian_proxy: http://apt-cacher:3142
" )
done

fly -t test set-pipeline -c example/pipeline.yml -p "$PIPELINE" -n \
  --var "setup-runtime-resource-tag=$HASH" \
  --var "tests=$TEST" \
  "${source_vars[@]}"

fly -t test unpause-pipeline -p "$PIPELINE"

# The git-server was just recreated, so its old commits are gone with it.
# -n, not `echo y |`: fly reads its confirmation from /dev/tty, so a piped answer
# is ignored - it then either bails out or, when a tty is present, blocks forever.
fly -t test clear-versions --resource="$PIPELINE/repo" -n || true

# Everything else - clearing task caches, the two runs per test, the assertions -
# happens inside this job, on the worker, exactly as it does in CI.
fly -t test trigger-job -j "$PIPELINE/test" --watch
