#!/bin/bash

set -euo pipefail

# Builds the resource image and starts the `test` job on the local stack; that job runs the same
# ci/tasks/run-tests.sh as CI, so a test passing here passes there.

TESTS_DIR="example/tests"
PIPELINE="${PIPELINE:-setup-runtime}"

TEST="${TEST:-}"

# full|fuse-only|ignore - what `privileged: true` tasks get on the local worker.
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
# The git-server builds its repo from the working tree at container start, so recreate it
# or tests run against a stale tree.
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

# One var per test holding its source.yml verbatim, as the deploying pipeline does for
# ci/pipeline.yml. The two rewrites below exist because this stack differs from CI's cluster.
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

# -n, not `echo y |`: fly reads its confirmation from /dev/tty, so a piped answer
# is ignored - it then either bails out or, when a tty is present, blocks forever.
fly -t test clear-versions --resource="$PIPELINE/repo" -n || true

fly -t test trigger-job -j "$PIPELINE/test" --watch
