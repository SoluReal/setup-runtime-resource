cd "$(mktemp -d)"
echo "java=21.0.4-tem" > .sdkmanrc
sdk env install

source ~/.bashrc
java --version | assert_contains "openjdk 21.0.4"
java --version | assert_contains "OpenJDK Runtime Environment Temurin-21.0.4"

mkdir subdir
echo "java=21.0.3-tem" > subdir/.sdkmanrc
cd subdir
sdk env install
java --version | assert_contains "openjdk 21.0.3"
java --version | assert_contains "OpenJDK Runtime Environment Temurin-21.0.3"

cd ..
sdk env install
java --version | assert_contains "openjdk 21.0.4"
java --version | assert_contains "OpenJDK Runtime Environment Temurin-21.0.4"

# `sdk` stores the repacked archive uncompressed and restores ZIPOPT. 21.0.3, as no source.yml bakes it,
# so `full` downloads it too.
unzip -v "$CACHE_DIRECTORY/sdkman-archives/java-21.0.3-tem.zip" | assert_contains " Stored "
echo "ZIPOPT=[${ZIPOPT-unset}]" | assert_contains "ZIPOPT=[unset]"
