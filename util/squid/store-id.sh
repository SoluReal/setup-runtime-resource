#!/bin/bash

# github.com/<repo>/releases/download redirects to a URL whose query is signed anew per request, so squid would never
# get a cache hit on a release asset. Keying the cache on the path alone (it names the asset) makes repeats hits.
while read -r url _; do
  echo "OK store-id=${url%%\?*}"
done
