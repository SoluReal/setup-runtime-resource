#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

if [[ "$s3_cache_enabled" != "true" ]]; then
  exit 0
fi

# Detect architecture
arch=$(uname -m)
case $arch in
  x86_64) rclone_arch="amd64" ;;
  aarch64) rclone_arch="arm64" ;;
  *) echo "Unsupported architecture: $arch"; exit 1 ;;
esac

# Unpinned by default: `rclone-current` is a stable URL rclone maintains.
if [[ -n "$s3_cache_rclone_version" ]]; then
  rclone_url="https://downloads.rclone.org/v${s3_cache_rclone_version}/rclone-v${s3_cache_rclone_version}-linux-${rclone_arch}.zip"
else
  rclone_url="https://downloads.rclone.org/rclone-current-linux-${rclone_arch}.zip"
fi

info "Installing rclone for $rclone_arch (S3 cache)"

(
  archive=$(mktemp)
  workdir=$(mktemp -d)
  curl_retry -fsSL "$rclone_url" -o "$archive"
  unzip -q -j "$archive" '*/rclone' -d "$workdir"
  install -D -m 0755 "$workdir/rclone" "$chroot_dir/usr/local/bin/rclone"
  rm -rf "$archive" "$workdir"
) &
info_spinner "Downloading rclone" "rclone installed" $!

cp "$ROOT_DIR/includes/s3cache.sh" "$chroot_dir/$RUNTIME_DIR/plugins/s3cache.sh"

# Non-secret configuration only. Credentials are task params, never `source`:
# `check` hashes `source` into the resource version, so putting them there would
# make every credential rotation rebuild the whole rootfs - and bake secrets into
# the pipeline config.
set_env "S3_CACHE_ENABLED=true"
set_env "S3_CACHE_BUCKET=$s3_cache_bucket"

if [[ -n "$s3_cache_provider" ]]; then
  set_env "S3_CACHE_PROVIDER=$s3_cache_provider"
fi

if [[ -n "$s3_cache_endpoint" ]]; then
  set_env "S3_CACHE_ENDPOINT=$s3_cache_endpoint"
fi

if [[ -n "$s3_cache_region" ]]; then
  set_env "S3_CACHE_REGION=$s3_cache_region"
fi

if [[ -n "$s3_cache_prefix" ]]; then
  set_env "S3_CACHE_PREFIX=$s3_cache_prefix"
fi

if [[ -n "$s3_cache_transfers" ]]; then
  set_env "S3_CACHE_TRANSFERS=$s3_cache_transfers"
fi

if [[ "$s3_cache_always_restore" = "true" ]]; then
  set_env "S3_CACHE_ALWAYS_RESTORE=true"
fi

if [[ "$s3_cache_gradle_build_cache" = "true" ]]; then
  set_env "S3_CACHE_GRADLE_BUILD_CACHE=true"
fi

if [[ -n "$s3_cache_extra_dirs" ]]; then
  set_env "S3_CACHE_EXTRA_DIRS=$s3_cache_extra_dirs"
fi

add_metadata "s3_cache" "$s3_cache_bucket"
