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

# Store the main pid so we can make sure that we only execute the traps on the main bash process.
if [ -n "$BASH_ENV" ]; then
  echo $$ > /tmp/main_pid
fi

unset BASH_ENV

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

    # Persist gradle.properties at build time
    mkdir -p /root/.gradle
    cat <<EOF > /root/.gradle/gradle.properties
org.gradle.caching=true
org.gradle.parallel=true
EOF
    # Overwrite gradle.properties with GRADLE_PROP_ environment variables
    while IFS='=' read -r name value ; do
      if [[ $name == GRADLE_PROP_* ]]; then
        prop_name=$(echo "${name#GRADLE_PROP_}" | tr '_' '.')
        # Remove existing property if it exists
        sed -i "/^${prop_name}=/d" /root/.gradle/gradle.properties
        echo "${prop_name}=${value}" >> /root/.gradle/gradle.properties
      fi
    done < <(env)

    mkdir -p /root/.m2
    cat <<EOF > /root/.m2/settings.xml
<settings>
  <localRepository>/root/.m2/repository</localRepository>
</settings>
EOF

    # It is possible that cache exists but that e.g. sdkman is no longer requested in the setup-runtime source.
    # Then the cache restore will break if we don't check for the existence of lz4.
    if command -v lz4 >/dev/null 2>&1; then
      LZ4_INSTALLED=true
    else
      LZ4_INSTALLED=false
    fi

    if [[ "$PYENV_ENABLED" = "true" && -f "$CACHE_DIRECTORY/pyenv/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
      info "Restoring pyenv versions from cache..."
      mkdir -p "$RUNTIME_DIR/pyenv"
      tar -I lz4 -xf "$CACHE_DIRECTORY/pyenv/archive.tar.lz4" -C "$RUNTIME_DIR/pyenv"
    fi
    if [[ "$NVM_ENABLED" = "true" && -f "$CACHE_DIRECTORY/nvm/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
      info "Restoring nvm versions from cache..."
      mkdir -p "$RUNTIME_DIR/nvm"
      tar -I lz4 -xf "$CACHE_DIRECTORY/nvm/archive.tar.lz4" -C "$RUNTIME_DIR/nvm"
    fi
    if [[ "$SDKMAN_ENABLED" = "true" && -f "$CACHE_DIRECTORY/sdkman/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
      info "Restoring sdkman candidates from cache..."
      mkdir -p "$RUNTIME_DIR/sdkman/candidates/"
      tar -I lz4 -xf "$CACHE_DIRECTORY/sdkman/archive.tar.lz4" -C "$RUNTIME_DIR/sdkman" candidates
    fi
    if [[ -f "$CACHE_DIRECTORY/gradle/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
      info "Restoring gradle cache..."
      mkdir -p /root/.gradle
      tar -I lz4 -xf "$CACHE_DIRECTORY/gradle/archive.tar.lz4" -C /root/.gradle
    fi
    if [[ -f "$CACHE_DIRECTORY/maven/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
      info "Restoring maven cache..."
      mkdir -p /root/.m2
      tar -I lz4 -xf "$CACHE_DIRECTORY/maven/archive.tar.lz4" -C /root/.m2
    fi
    if [[ -d "$RUNTIME_DIR/docker" ]]; then
      info "Restoring docker images"
      docker_load_cache
    fi
  fi
fi

function prepare_cache() {
  if [[ "$ENABLE_CACHE" = "true" ]]; then
    if [[ ! -f /tmp/runtime-cache-prepared ]]; then
      touch /tmp/runtime-cache-prepared
      if [[ "$PYENV_ENABLED" = "true" && -d "$RUNTIME_DIR/pyenv/versions" ]]; then
        info "Saving pyenv versions to cache..."
        mkdir -p "$CACHE_DIRECTORY/pyenv"
        tar -I lz4 -cf "$CACHE_DIRECTORY/pyenv/archive.tar.lz4" -C "$RUNTIME_DIR/pyenv" versions
      fi
      if [[ "$NVM_ENABLED" = "true" && -d "$RUNTIME_DIR/nvm/versions" ]]; then
        info "Saving nvm versions to cache..."
        mkdir -p "$CACHE_DIRECTORY/nvm"
        tar -I lz4 -cf "$CACHE_DIRECTORY/nvm/archive.tar.lz4" -C "$RUNTIME_DIR/nvm" versions
      fi
      if [[ "$SDKMAN_ENABLED" = "true" && -d "$RUNTIME_DIR/sdkman/candidates" ]]; then
        info "Saving sdkman candidates to cache..."
        mkdir -p "$CACHE_DIRECTORY/sdkman"
        tar -I lz4 -cf "$CACHE_DIRECTORY/sdkman/archive.tar.lz4" -C "$RUNTIME_DIR/sdkman/" candidates
      fi
      if [[ -d "/root/.gradle" ]]; then
        info "Saving gradle cache..."
        mkdir -p "$CACHE_DIRECTORY/gradle"
        # Only cache what is needed
        # caches/modules-2
        # wrapper/dists
        tar -I lz4 -cf "$CACHE_DIRECTORY/gradle/archive.tar.lz4" \
          -C /root/.gradle \
          --transform='s,^caches/modules-2,caches/modules-2,' \
          --transform='s,^caches/build-cache-1,caches/build-cache-1,' \
          --transform='s,^caches/jars-9,caches/jars-9,' \
          --transform='s,^wrapper/dists,wrapper/dists,' \
          --transform='s,^configuration-cache,configuration-cache,' \
          caches/jars-9 caches/modules-2 wrapper/dists caches/build-cache-1 configuration-cache 2>/dev/null || true
      fi
      if [[ -d "/root/.m2/repository" ]]; then
        info "Saving maven cache..."
        mkdir -p "$CACHE_DIRECTORY/maven"
        tar -I lz4 -cf "$CACHE_DIRECTORY/maven/archive.tar.lz4" -C /root/.m2 repository
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

      if [[ "$DEBUG" = "true" ]]; then
        info "Cache size in $CACHE_DIR:"
        info "$(du -sh "$CACHE_DIRECTORY" 2>/dev/null)" || true
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
