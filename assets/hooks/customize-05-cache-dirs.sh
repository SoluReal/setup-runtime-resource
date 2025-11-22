#!/bin/bash

set -e

rootdir="$1"

mkdir -p $rootdir/cache/npm
echo "export NPM_CONFIG_CACHE=/cache/npm" >> $rootdir/root/.bashrc

mkdir -p $rootdir/cache/yarn
echo "export YARN_CACHE_FOLDER=/cache/yarn" >> $rootdir/root/.bashrc

mkdir -p $rootdir/cache/pnpm
echo "export PNPM_STORE_PATH=/cache/pnpm" >> $rootdir/root/.bashrc

mkdir -p $rootdir/cache/gradle
echo "export GRADLE_USER_HOME=/cache/gradle" >> $rootdir/root/.bashrc

mkdir $rootdir/cache/maven
mkdir -p $rootdir/.m2
touch $rootdir/.m2/settings.xml
echo '<settings><localRepository>/cache/maven</localRepository></settings>' > $rootdir/.m2/settings.xml
