# File is included in the bashrc file and is expected to be executed on task startup.

# Reset
export Color_Off='\033[0m' # Text Reset

# To print to console with colors
export Red='\033[0;31m'    # Red
export Green='\033[0;32m'  # Green
export RUNTIME_DIR="/var/runtimes"

function info() {
  printf "$Green%s$Color_Off\n" "$1"
}

function error() {
  printf "$Red%s$Color_Off\n" "$1" >&2
}


CACHE_DIR="${CACHE_DIR:-cache}"
export ENABLE_CACHE="${ENABLE_CACHE:-true}"
export CACHE_DIRECTORY="$(pwd)/$CACHE_DIR"

if [[ -d "$RUNTIME_DIR/docker" ]]; then
  source $RUNTIME_DIR/docker/docker-functions.sh
  source $RUNTIME_DIR/docker/docker-cache.sh
fi

if [[ ! -f /tmp/runtime-prep-applied ]]; then
  touch /tmp/runtime-prep-applied

  if [[ -d "$RUNTIME_DIR/docker" ]]; then
    source $RUNTIME_DIR/docker/docker-functions.sh

    # Waits DOCKERD_TIMEOUT seconds for startup (default: 60)
    DOCKERD_TIMEOUT="${DOCKERD_TIMEOUT:-60}"
    # Accepts optional DOCKER_OPTS (default: --data-root /scratch/docker)
    DOCKER_OPTS="${DOCKER_OPTS:-}"

    # Constants
    DOCKERD_PID_FILE="/tmp/docker.pid"
    DOCKERD_LOG_FILE="/tmp/docker.log"

    if grep -q cgroup2 /proc/filesystems; then
      cgroups_version='v2'
    else
      cgroups_version='v1'
    fi

    start_docker
    await_docker
    echo "$(date +%s)" > /tmp/docker-start
  fi

  if [[ "$ENABLE_CACHE" = "true" ]]; then
    mkdir -p "$CACHE_DIRECTORY"

    if [[ "$DEBUG" = "true" ]]; then
      info "Cache size in $CACHE_DIRECTORY:"
      info "$(du -sh "$CACHE_DIRECTORY" 2>/dev/null)" || true
    fi

    mkdir -p $CACHE_DIRECTORY/npm
    echo "export NPM_CONFIG_CACHE=$CACHE_DIRECTORY/npm" >> /root/.bashrc

    mkdir -p $CACHE_DIRECTORY/yarn
    echo "export YARN_CACHE_FOLDER=$CACHE_DIRECTORY/yarn" >> /root/.bashrc

    mkdir -p $CACHE_DIRECTORY/pnpm
    echo "export PNPM_STORE_PATH=$CACHE_DIRECTORY/pnpm" >> /root/.bashrc

    mkdir -p $CACHE_DIRECTORY/gradle
    echo "export GRADLE_USER_HOME=$CACHE_DIRECTORY/gradle" >> /root/.bashrc

    # Persist gradle.properties at build time
    mkdir -p /root/.gradle
    cat <<EOF > /root/.gradle/gradle.properties
org.gradle.caching=true
org.gradle.parallel=true
EOF

    mkdir -p "$CACHE_DIRECTORY/maven"
    mkdir -p /root/.m2
    touch /root/.m2/settings.xml
    echo "<settings><localRepository>$CACHE_DIRECTORY/maven</localRepository></settings>" > /root/.m2/settings.xml

    if [[ "$PYENV_ENABLED" = "true" && -d "$CACHE_DIRECTORY/pyenv/versions" ]]; then
      info "Restoring pyenv versions from cache..."
      mkdir -p "$RUNTIME_DIR/pyenv/versions/"
      cp -a "$CACHE_DIRECTORY/pyenv/versions/" "$RUNTIME_DIR/pyenv/"
    fi
    if [[ "$NVM_ENABLED" = "true" && -d "$CACHE_DIRECTORY/nvm/versions" ]]; then
      info "Restoring nvm versions from cache..."
      mkdir -p "$RUNTIME_DIR/nvm/versions/"
      cp -a "$CACHE_DIRECTORY/nvm/versions/" "$RUNTIME_DIR/nvm/"
    fi
    if [[ "$SDKMAN_ENABLED" = "true" && -d "$CACHE_DIRECTORY/sdkman/candidates" ]]; then
      info "Restoring sdkman candidates from cache..."
      mkdir -p "$RUNTIME_DIR/sdkman/candidates/"
      cp -a "$CACHE_DIRECTORY/sdkman/candidates/" "$RUNTIME_DIR/sdkman/"
    fi
    if [[ -d "$RUNTIME_DIR/docker" ]]; then
      info "Restoring docker images"
      docker_load_cache
    fi
  fi
fi

function prepare_cache() {
  if [[ "$ENABLE_CACHE" = "true" ]]; then
    if [[ "$PYENV_ENABLED" = "true" && -d "$RUNTIME_DIR/pyenv/versions" ]]; then
      info "Saving pyenv versions to cache..."
      mkdir -p "$CACHE_DIRECTORY/pyenv"
      cp -a "$RUNTIME_DIR/pyenv/versions/" "$CACHE_DIRECTORY/pyenv/"
    fi
    if [[ "$NVM_ENABLED" = "true" && -d "$RUNTIME_DIR/nvm/versions" ]]; then
      info "Saving nvm versions to cache..."
      mkdir -p "$CACHE_DIRECTORY/nvm"
      cp -a "$RUNTIME_DIR/nvm/versions/" "$CACHE_DIRECTORY/nvm/"
    fi
    if [[ "$SDKMAN_ENABLED" = "true" && -d "$RUNTIME_DIR/sdkman/candidates" ]]; then
      info "Saving sdkman candidates to cache..."
      mkdir -p "$CACHE_DIRECTORY/sdkman"
      cp -a "$RUNTIME_DIR/sdkman/candidates/" "$CACHE_DIRECTORY/sdkman/"
    fi

    if [[ ! -d "$CACHE_DIRECTORY" ]]; then
      return 0
    fi

    size_bytes=$(du -sb "$CACHE_DIRECTORY" | awk '{print $1}')

    if [[ -n "$MAX_CACHE_SIZE_MB" ]]; then
      local max_size=$(($MAX_CACHE_SIZE_MB * 1024 * 1024))

      if (( size_bytes > max_size )); then
        info "Cache size is $(du -sh "$CACHE_DIRECTORY" 2>/dev/null) which is above $MAX_CACHE_SIZE_MB MB. Cleaning up $CACHE_DIRECTORY..."
        rm -rf "$CACHE_DIRECTORY/*" || true
        info "Cleanup completed."
      fi
    fi
  else
    # Don't fail on this, you can receive Device or resource busy
    rm -rf "$CACHE_DIRECTORY/*" || true
  fi
}

if [[ "$PYENV_ENABLED" = "true" ]]; then
  eval "$(pyenv init - bash)"
fi
