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
