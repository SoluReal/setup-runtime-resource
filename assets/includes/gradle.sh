#!/bin/bash

export GRADLE_USER_HOME="$CACHE_DIRECTORY/gradle"

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

# caches/jars-9, build-cache-1 and configuration-cache are deliberately absent:
# all three are derived, and tied to a Gradle version or a checkout path.
register_cache_dir gradle/modules-2 "$GRADLE_USER_HOME/caches/modules-2"
register_cache_dir gradle/wrapper-dists "$GRADLE_USER_HOME/wrapper/dists"

register_initialize_callback prepare_gradle_config
