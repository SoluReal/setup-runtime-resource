#!/bin/bash

export GRADLE_USER_HOME="$CACHE_DIRECTORY/gradle"

function prepare_gradle_config() {
  mkdir -p "$GRADLE_USER_HOME"
  cat <<EOF > "$GRADLE_USER_HOME"/gradle.properties
org.gradle.caching=true
org.gradle.parallel=true
# The default <project>/.gradle is a fresh checkout every build, so the config cache would never be reused.
org.gradle.projectcachedir=$GRADLE_USER_HOME
EOF
  while IFS='=' read -r name value ; do
    if [[ $name == GRADLE_PROP_* ]]; then
      prop_name=$(echo "${name#GRADLE_PROP_}" | tr '_' '.')
      sed -i "/^${prop_name}=/d" "$GRADLE_USER_HOME"/gradle.properties
      echo "${prop_name}=${value}" >> "$GRADLE_USER_HOME"/gradle.properties
    fi
  done < <(env)
}

# Logging only: all of GRADLE_USER_HOME persists, but only downloads are worth reporting.
register_cache_dir gradle/modules-2 "$GRADLE_USER_HOME/caches/modules-2"
register_cache_dir gradle/wrapper-dists "$GRADLE_USER_HOME/wrapper/dists"

register_initialize_callback prepare_gradle_config
