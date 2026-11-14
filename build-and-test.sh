#!/bin/bash

set -euo pipefail

# Builds the resource image and starts the `test` job on the local stack; that job runs the same
# ci/tasks/run-tests.sh as CI, so a test passing here passes there.

TESTS_DIR="test/resources"

PIPELINE="${PIPELINE:-setup-runtime}"

TEST="${TEST:-}"

export CONCOURSE_CONTAINERD_PRIVILEGED_MODE="${CONCOURSE_CONTAINERD_PRIVILEGED_MODE:-full}"

available_tests() {
  local dir
  for dir in "$TESTS_DIR"/*/; do
    [[ -f "$dir/source.yml" && -f "$dir/test.sh" ]] && basename "$dir"
  done
  echo full
}

for name in $TEST; do
  if [[ "$name" != full && ! -f "$TESTS_DIR/$name/test.sh" ]]; then
    echo "Unknown test '$name'. Available:" >&2
    available_tests | sed 's/^/  /' >&2
    exit 1
  fi
done

echo "Running setup-runtime tests: ${TEST:-all}"

docker-compose -p concource-resource -f docker-compose.yml up -d --build
# The git-server commits test/ and ci/ only at container start, so recreate it for the current tree.
docker-compose -p concource-resource -f docker-compose.yml up -d --force-recreate git-server

IMAGE_TAG="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8; echo)"

docker buildx build \
  -t localhost:5000/setup-runtime-resource:latest \
  -t localhost:5000/setup-runtime-resource:$IMAGE_TAG \
  --progress=plain \
  --push .

until fly -t test login -c http://localhost:8080 -u test -p test
do
  sleep 5
done

# Same generator as the deploy of ci/pipeline.yml; the flags cover how this stack differs from CI's cluster:
# no unprivileged user namespaces (so dockerd, not rootless podman), an apt-cacher and a caching proxy.
command -v yq > /dev/null || { echo "test/pipeline.sh needs mikefarah yq v4 (brew install yq)" >&2; exit 1; }
pipeline_file="$(mktemp)"
proxy_ca_file="$(mktemp)"
trap 'rm -f "$pipeline_file" "$proxy_ca_file"' EXIT
# squid writes its CA on first start; it persists in a volume, so the sources (and their rootfs) stay the same.
for _ in $(seq 1 30); do
  docker-compose -p concource-resource -f docker-compose.yml exec -T squid cat /etc/squid/ca/ca.pem \
    > "$proxy_ca_file" 2> /dev/null && break
  sleep 1
done
[[ -s "$proxy_ca_file" ]] || { echo "squid did not write its CA; see docker-compose logs squid" >&2; exit 1; }
test/pipeline.sh test/pipeline.yml --no-rootless --debian-proxy http://apt-cacher:3142 \
  --proxy http://squid:3128 --proxy-ca "$proxy_ca_file" > "$pipeline_file"

fly -t test set-pipeline -c "$pipeline_file" -p "$PIPELINE" -n \
  --var "setup-runtime-resource-tag=$IMAGE_TAG" \
  --var "tests=$TEST"

fly -t test unpause-pipeline -p "$PIPELINE"

# -n, not `echo y |`: fly reads its confirmation from /dev/tty, so a piped answer
# is ignored - it then either bails out or, when a tty is present, blocks forever.
fly -t test clear-versions --resource="$PIPELINE/repo" -n || true

fly -t test trigger-job -j "$PIPELINE/test" --watch
