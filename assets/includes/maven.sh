#!/bin/bash

export MAVEN_USER_HOME="$CACHE_DIRECTORY/maven"
export MAVEN_LOCAL_REPO="$MAVEN_USER_HOME/repository"

function create_m2_dir() {
    mkdir -p "$RUNTIME_HOME/.m2" "$MAVEN_USER_HOME" "$MAVEN_LOCAL_REPO"
    cat <<EOF > $RUNTIME_HOME/.m2/settings.xml
<settings>
<localRepository>$MAVEN_LOCAL_REPO</localRepository>
</settings>
EOF
    cp "$RUNTIME_HOME/.m2/settings.xml" "$MAVEN_USER_HOME/settings.xml"
}

register_cache_dir maven/repository "$MAVEN_LOCAL_REPO"
register_cache_dir maven/wrapper-dists "$MAVEN_USER_HOME/wrapper/dists"

register_initialize_callback create_m2_dir
register_teardown_callback create_m2_dir
