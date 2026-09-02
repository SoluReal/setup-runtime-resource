#!/bin/bash

export GRADLE_USER_HOME="$CACHE_DIRECTORY/gradle"

# What goes to the S3 tier:
#
#   caches/modules-2   the dependency cache - immutable, version-addressed, and
#                      the expensive thing to refetch. The main win.
#   wrapper/dists      Gradle distributions the wrapper downloads (~150MB each),
#                      immutable per version.
#
# Deliberately not uploaded:
#   caches/jars-9        derived, instrumented jars keyed to the Gradle version;
#                        cheap to regenerate and version-sensitive.
#   caches/build-cache-1 task *output* cache. Uploads on every code change for a
#                        much lower hit rate than a dependency cache. Opt in with
#                        s3_cache.gradle_build_cache.
#   configuration-cache  bound to the exact invocation and environment, not
#                        portable between machines or checkout paths.
#
# All of them still persist locally between builds on the same worker, because
# the whole directory is the cache volume.
GRADLE_S3_MODULES_KEY="gradle/modules-2"
GRADLE_S3_WRAPPER_KEY="gradle/wrapper-dists"
GRADLE_S3_BUILD_CACHE_KEY="gradle/build-cache-1"

GRADLE_S3_EXCLUDES=(
  --exclude "**/*.lck"
  --exclude "**/*.lock"
  --exclude "**/*.part"
)

function prepare_gradle_config() {
  # Persist gradle.properties at build time
  mkdir -p "$GRADLE_USER_HOME"
  cat <<EOF > "$GRADLE_USER_HOME"/gradle.properties
org.gradle.caching=true
org.gradle.parallel=true
# The configuration cache lives in the project cache dir, which defaults to
# <project>/.gradle - a fresh checkout on every CI build, so it would never be
# reused.
org.gradle.projectcachedir=$GRADLE_USER_HOME
EOF
  # Overwrite gradle.properties with GRADLE_PROP_ environment variables
  while IFS='=' read -r name value ; do
    if [[ $name == GRADLE_PROP_* ]]; then
      prop_name=$(echo "${name#GRADLE_PROP_}" | tr '_' '.')
      # Remove existing property if it exists
      sed -i "/^${prop_name}=/d" "$GRADLE_USER_HOME"/gradle.properties
      echo "${prop_name}=${value}" >> "$GRADLE_USER_HOME"/gradle.properties
    fi
  done < <(env)
}

function prepare_gradle_cache() {
  if [[ "$ENABLE_CACHE" != "true" || ! -d "$GRADLE_USER_HOME" ]]; then
    return 0
  fi

  s3cache_save "$GRADLE_USER_HOME/caches/modules-2" "$GRADLE_S3_MODULES_KEY" "${GRADLE_S3_EXCLUDES[@]}"
  s3cache_save "$GRADLE_USER_HOME/wrapper/dists" "$GRADLE_S3_WRAPPER_KEY" "${GRADLE_S3_EXCLUDES[@]}"

  if [[ "$S3_CACHE_GRADLE_BUILD_CACHE" = "true" ]]; then
    # Task outputs change often, so cache them only when explicitly requested.
    s3cache_save "$GRADLE_USER_HOME/caches/build-cache-1" "$GRADLE_S3_BUILD_CACHE_KEY" "${GRADLE_S3_EXCLUDES[@]}"
  fi
}

# Non-empty means the local tier is warm: the cache volume already holds it and
# no network call is needed.
function gradle_cache_is_cold() {
  [[ "$S3_CACHE_ALWAYS_RESTORE" = "true" ]] && return 0
  [[ -z "$(ls -A "$1" 2>/dev/null)" ]]
}

function restore_gradle_cache() {
  if [[ "$ENABLE_CACHE" != "true" ]]; then
    return 0
  fi

  # Gradle refetches missing modules after a partial restore.
  if gradle_cache_is_cold "$GRADLE_USER_HOME/caches/modules-2"; then
    s3cache_restore "$GRADLE_USER_HOME/caches/modules-2" "$GRADLE_S3_MODULES_KEY" "${GRADLE_S3_EXCLUDES[@]}" || true
  else
    cache_local_hit "$GRADLE_S3_MODULES_KEY" "$GRADLE_USER_HOME/caches/modules-2"
  fi

  if ! gradle_cache_is_cold "$GRADLE_USER_HOME/wrapper/dists"; then
    cache_local_hit "$GRADLE_S3_WRAPPER_KEY" "$GRADLE_USER_HOME/wrapper/dists"
  else
    local rc=0
    s3cache_restore "$GRADLE_USER_HOME/wrapper/dists" "$GRADLE_S3_WRAPPER_KEY" "${GRADLE_S3_EXCLUDES[@]}" || rc=$?
    if [[ $rc -eq 1 && -d "$GRADLE_USER_HOME/wrapper/dists" ]]; then
      error "Discarding partially restored gradle distributions; the wrapper will download them"
      rm -rf "$GRADLE_USER_HOME/wrapper/dists"
    fi
  fi

  if [[ "$S3_CACHE_GRADLE_BUILD_CACHE" = "true" ]]; then
    if gradle_cache_is_cold "$GRADLE_USER_HOME/caches/build-cache-1"; then
      s3cache_restore "$GRADLE_USER_HOME/caches/build-cache-1" "$GRADLE_S3_BUILD_CACHE_KEY" "${GRADLE_S3_EXCLUDES[@]}" || true
    else
      cache_local_hit "$GRADLE_S3_BUILD_CACHE_KEY" "$GRADLE_USER_HOME/caches/build-cache-1"
    fi
  fi
}

register_initialize_callback prepare_gradle_config
register_initialize_callback restore_gradle_cache
register_teardown_callback prepare_gradle_cache
