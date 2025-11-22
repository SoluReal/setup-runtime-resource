#!/bin/bash

set -e

chroot_dir="$1"

mkdir -p $chroot_dir/cache/npm
echo "export NPM_CONFIG_CACHE=/cache/npm" >> $chroot_dir/root/.bashrc

mkdir -p $chroot_dir/cache/yarn
echo "export YARN_CACHE_FOLDER=/cache/yarn" >> $chroot_dir/root/.bashrc

mkdir -p $chroot_dir/cache/pnpm
echo "export PNPM_STORE_PATH=/cache/pnpm" >> $chroot_dir/root/.bashrc

mkdir -p $chroot_dir/cache/gradle
echo "export GRADLE_USER_HOME=/cache/gradle" >> $chroot_dir/root/.bashrc

mkdir $chroot_dir/cache/maven
mkdir -p $chroot_dir/.m2
touch $chroot_dir/.m2/settings.xml
echo '<settings><localRepository>/cache/maven</localRepository></settings>' > $chroot_dir/.m2/settings.xml
