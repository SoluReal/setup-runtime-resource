# The properties file is written at shell start, so regenerate it with the override.
export GRADLE_PROP_org_gradle_parallel=false
prepare_gradle_config

echo "$GRADLE_USER_HOME" | assert_contains "$CACHE_DIRECTORY/gradle"
cat "$GRADLE_USER_HOME/gradle.properties" | assert_contains "org.gradle.caching=true"
cat "$GRADLE_USER_HOME/gradle.properties" | assert_contains "org.gradle.parallel=false"

cd "$PROJECTS/gradle"
sdk env install
./gradlew clean build
