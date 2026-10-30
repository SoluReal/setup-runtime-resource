#!/bin/bash

# SDKMAN only puts a candidate on PATH while sourcing sdkman-init.sh, and only
# if its `current` symlink already exists. `sdk use` / `sdk env install` rewrite
# an sdkman PATH entry but never add one, so a candidate that appears later in
# the task gets its *_HOME exported but stays off PATH. Seeding the
# `current/bin` entries up front fixes that: a non-existing PATH entry is
# skipped during lookup until it exists.
SDKMAN_CANDIDATES_DIR="$RUNTIME_DIR/sdkman/candidates"
export PATH="$SDKMAN_CANDIDATES_DIR/java/current/bin:$SDKMAN_CANDIDATES_DIR/maven/current/bin:$SDKMAN_CANDIDATES_DIR/gradle/current/bin:$PATH"
