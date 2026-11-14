#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"
source "$ROOT_DIR/installers/proxy.sh"

# After every JDK install; the build's own downloads already trust the CA through the host's store.
proxy_trust_rootfs "$chroot_dir"
