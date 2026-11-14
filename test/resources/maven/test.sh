echo "$MAVEN_USER_HOME" | assert_contains "$CACHE_DIRECTORY/maven"
echo "$MAVEN_LOCAL_REPO" | assert_contains "$CACHE_DIRECTORY/maven/repository"
cat "$RUNTIME_HOME/.m2/settings.xml" | assert_contains "<localRepository>$MAVEN_LOCAL_REPO</localRepository>"
cat "$MAVEN_USER_HOME/settings.xml" | assert_contains "<localRepository>$MAVEN_LOCAL_REPO</localRepository>"

cd "$PROJECTS/maven"
sdk env install
./mvnw clean install
