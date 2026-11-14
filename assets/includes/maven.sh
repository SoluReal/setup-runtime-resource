#!/bin/bash

export MAVEN_USER_HOME="$CACHE_DIRECTORY/maven"
export MAVEN_LOCAL_REPO="$MAVEN_USER_HOME/repository"
# Java takes user.home from passwd, not $HOME, so a root task would read /root/.m2 and miss the cache.
case " ${MAVEN_ARGS:-} " in
  *" -Dmaven.repo.local="*) ;;
  *) export MAVEN_ARGS="${MAVEN_ARGS:+$MAVEN_ARGS }-Dmaven.repo.local=$MAVEN_LOCAL_REPO" ;;
esac

function create_m2_dir() {
    mkdir -p "$RUNTIME_HOME/.m2" "$MAVEN_USER_HOME" "$MAVEN_LOCAL_REPO"
    {
      echo "<settings>"
      echo "<localRepository>$MAVEN_LOCAL_REPO</localRepository>"
      # Set by the resource's proxy option; Maven ignores *_proxy.
      if [[ -n "${SETUP_RUNTIME_PROXY_HOST:-}" ]]; then
        echo "<proxies>"
        local scheme
        for scheme in http https; do
          echo "<proxy><id>setup-runtime-$scheme</id><active>true</active><protocol>$scheme</protocol>"
          echo "<host>$SETUP_RUNTIME_PROXY_HOST</host><port>$SETUP_RUNTIME_PROXY_PORT</port>"
          echo "<nonProxyHosts>$SETUP_RUNTIME_NON_PROXY_HOSTS</nonProxyHosts></proxy>"
        done
        echo "</proxies>"
      fi
      echo "</settings>"
    } > $RUNTIME_HOME/.m2/settings.xml
    cp "$RUNTIME_HOME/.m2/settings.xml" "$MAVEN_USER_HOME/settings.xml"
}

register_cache_dir maven/repository "$MAVEN_LOCAL_REPO"
register_cache_dir maven/wrapper-dists "$MAVEN_USER_HOME/wrapper/dists"

register_initialize_callback create_m2_dir
register_teardown_callback create_m2_dir
