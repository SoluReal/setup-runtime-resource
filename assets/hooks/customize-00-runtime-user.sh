#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR"/common.sh
time_hook "$0"

# Tasks run as this user, so it must exist in every rootfs. Written directly: useradd's auto-assigned
# subuid/subgid ranges collide with the explicit ones below and break newuidmap.
echo "$RUNTIME_USER:x:$RUNTIME_UID:$RUNTIME_UID:runtime:$RUNTIME_HOME:/bin/bash" >> "$chroot_dir/etc/passwd"
# 19000 is an arbitrary last-changed day; password auth is unused.
echo "$RUNTIME_USER:!:19000:0:99999:7:::" >> "$chroot_dir/etc/shadow"
echo "$RUNTIME_USER:x:$RUNTIME_UID:" >> "$chroot_dir/etc/group"

echo "$RUNTIME_USER:100000:65536" >> "$chroot_dir/etc/subuid"
echo "$RUNTIME_USER:100000:65536" >> "$chroot_dir/etc/subgid"

mkdir -p "$chroot_dir$RUNTIME_HOME"
chown "$RUNTIME_UID:$RUNTIME_UID" "$chroot_dir$RUNTIME_HOME"
