#!/bin/bash

# sdkman puts a candidate on PATH only if its `current` symlink exists at init, and `sdk use`
# never adds one; seeding current/bin up front works since missing PATH entries are skipped.
SDKMAN_CANDIDATES_DIR="$RUNTIME_DIR/sdkman/candidates"
export PATH="$SDKMAN_CANDIDATES_DIR/java/current/bin:$SDKMAN_CANDIDATES_DIR/maven/current/bin:$SDKMAN_CANDIDATES_DIR/gradle/current/bin:$PATH"
