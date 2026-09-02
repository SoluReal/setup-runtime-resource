#!/bin/bash

export MAVEN_USER_HOME="$CACHE_DIRECTORY/maven"
export MAVEN_LOCAL_REPO="$MAVEN_USER_HOME/repository"

MAVEN_S3_CACHE_KEY="maven/repository"
MAVEN_S3_WRAPPER_KEY="maven/wrapper-dists"

# Maven's own bookkeeping files must never reach the bucket: *.lastUpdated and
# _remote.repositories record a failed resolution, and restoring one would make
# every later build skip retrying that artifact. The rest are transient state.
MAVEN_S3_EXCLUDES=(
  --exclude "**/*.lastUpdated"
  --exclude "**/_remote.repositories"
  --exclude "**/*.part"
  --exclude "**/*.lock"
  --exclude "**/resolver-status.properties"
)

function create_m2_dir() {
    mkdir -p "$RUNTIME_HOME/.m2" "$MAVEN_USER_HOME" "$MAVEN_LOCAL_REPO"
    cat <<EOF > $RUNTIME_HOME/.m2/settings.xml
<settings>
<localRepository>$MAVEN_LOCAL_REPO</localRepository>
</settings>
EOF
    cp "$RUNTIME_HOME/.m2/settings.xml" "$MAVEN_USER_HOME/settings.xml"
}

function prepare_maven_cache() {
  if [[ "$ENABLE_CACHE" != "true" ]]; then
    return 0
  fi

  if [[ -d "$MAVEN_LOCAL_REPO" ]]; then
    s3cache_save "$MAVEN_LOCAL_REPO" "$MAVEN_S3_CACHE_KEY" "${MAVEN_S3_EXCLUDES[@]}"
  fi

  s3cache_save "$MAVEN_USER_HOME/wrapper/dists" "$MAVEN_S3_WRAPPER_KEY" "${MAVEN_S3_EXCLUDES[@]}"
}

# Non-empty means the local tier is warm: the cache volume already holds it and
# no network call is needed.
function maven_cache_is_cold() {
  [[ "$S3_CACHE_ALWAYS_RESTORE" = "true" ]] && return 0
  [[ -z "$(ls -A "$1" 2>/dev/null)" ]]
}

function restore_maven_cache() {
  if [[ "$ENABLE_CACHE" != "true" ]]; then
    return 0
  fi

  if maven_cache_is_cold "$MAVEN_LOCAL_REPO"; then
    s3cache_restore "$MAVEN_LOCAL_REPO" "$MAVEN_S3_CACHE_KEY" "${MAVEN_S3_EXCLUDES[@]}" || true
  else
    cache_local_hit "$MAVEN_S3_CACHE_KEY" "$MAVEN_LOCAL_REPO"
  fi

  if ! maven_cache_is_cold "$MAVEN_USER_HOME/wrapper/dists"; then
    cache_local_hit "$MAVEN_S3_WRAPPER_KEY" "$MAVEN_USER_HOME/wrapper/dists"
  else
    local rc=0
    s3cache_restore "$MAVEN_USER_HOME/wrapper/dists" "$MAVEN_S3_WRAPPER_KEY" "${MAVEN_S3_EXCLUDES[@]}" || rc=$?
    if [[ $rc -eq 1 && -d "$MAVEN_USER_HOME/wrapper/dists" ]]; then
      error "Discarding partially restored maven distributions; the wrapper will download them"
      rm -rf "$MAVEN_USER_HOME/wrapper/dists"
    fi
  fi
}

register_initialize_callback create_m2_dir
register_initialize_callback restore_maven_cache
register_teardown_callback prepare_maven_cache
register_teardown_callback create_m2_dir
