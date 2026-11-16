# Set by the resource only for the rootless variant; locally dockerd runs as root instead.
if [[ "${TESTCONTAINERS_ROOTLESS:-}" == "true" ]]; then
  echo "=== rootless sanity checks ==="
  id -un | assert_contains "runtime"
  [[ "$(id -u)" != "0" ]] || { echo "task should not run as root"; exit 1; }

  docker info | assert_contains "rootless: true"

  stat --format="%U" "${DOCKER_HOST#unix://}" | assert_contains "runtime"
  command -v dockerd && { echo "dockerd should not be installed in rootless mode"; exit 1; } || true
fi

echo "=== docker build and run ==="
cd "$(mktemp -d)"
echo "FROM alpine" > Dockerfile
docker build -t runtime-test .

docker run -d --name nginx-server -p 8080:80 docker.io/nginx
sleep 5
docker stop nginx-server

docker run -d --name nginx-server-old -p 8080:80 docker.io/nginx:1.28.0
sleep 5
docker stop nginx-server-old

echo "=== fetching a real Spring Boot + Testcontainers project ==="
cd "$(mktemp -d)"
curl -fsSL -o starter.tgz \
  "https://start.spring.io/starter.tgz?type=gradle-project-kotlin&language=kotlin&platformVersion=4.1.0&packaging=jar&configurationFileFormat=properties&javaVersion=21&groupId=com.example&artifactId=demo&packageName=com.example.demo&dependencies=testcontainers"
mkdir -p demo
tar xzf starter.tgz -C demo --warning=no-unknown-keyword
cd demo

cat > src/test/kotlin/com/example/demo/RedisContainerTest.kt <<'KOTLIN'
package com.example.demo

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.wait.strategy.Wait
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import java.net.Socket

@Testcontainers
class RedisContainerTest {

    companion object {
        @Container
        @JvmStatic
        val redis: GenericContainer<*> = GenericContainer("redis:7-alpine")
            .withExposedPorts(6379)
            .waitingFor(Wait.forListeningPort())
    }

    @Test
    fun `redis container starts and answers PING`() {
        assertTrue(redis.isRunning)

        Socket(redis.host, redis.getMappedPort(6379)).use { socket ->
            socket.getOutputStream().write("PING\r\n".toByteArray())
            socket.getOutputStream().flush()

            val reply = socket.getInputStream()
                .readNBytes(7)
                .toString(Charsets.UTF_8)

            assertEquals("+PONG\r\n", reply)
        }
    }
}
KOTLIN

echo "=== running the test suite ==="
./gradlew clean test --rerun --info
