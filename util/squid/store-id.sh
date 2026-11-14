#!/bin/bash

# Squid store_id helper for GitHub release assets: the query is a new signature per request, the path names the asset.
while read -r url _; do
  echo "OK store-id=${url%%\?*}"
done
