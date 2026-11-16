echo $PATH | assert_contains "/var/runtimes/sdkman/candidates/java/current/bin"

java --version | assert_contains "openjdk 21.0.4"
java --version | assert_contains "OpenJDK Runtime Environment Temurin-21.0.4"

# `jar` lives next to `java` in the sdkman candidate bin, so it only resolves
# when that dir is on PATH - not just when JAVA_HOME points at it.
command -v jar | assert_contains "/var/runtimes/sdkman/candidates/java/current/bin/jar"

gradle --version | assert_contains "Gradle 8.5"
mvn --version | assert_contains "Apache Maven 3.9.9"

# minimal_image strips jmods from every installed JDK.
ls /var/runtimes/sdkman/candidates/java/*/jmods 2>&1 | assert_contains "No such file"

sdk use java 25-graalce
java --version | assert_contains "openjdk 25"
java --version | assert_contains "OpenJDK Runtime Environment GraalVM CE 25"
native-image --help | assert_contains "This tool can ahead-of-time compile Java code to native executables."
