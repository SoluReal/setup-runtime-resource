package com.example.demo

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.wait.strategy.Wait
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

@Testcontainers
class NginxContainerTest {

    companion object {
        @Container
        @JvmStatic
        val nginx: GenericContainer<*> = GenericContainer("nginx:latest")
            .withExposedPorts(80)
            .waitingFor(Wait.forHttp("/").forStatusCode(200))
    }

    @Test
    fun `nginx container starts and serves the welcome page`() {
        assertTrue(nginx.isRunning)

        val uri = URI("http://${nginx.host}:${nginx.getMappedPort(80)}/")
        val request = HttpRequest.newBuilder(uri).GET().build()
        val response = HttpClient.newHttpClient()
            .send(request, HttpResponse.BodyHandlers.ofString())

        assertEquals(200, response.statusCode())
        assertTrue(response.body().contains("Welcome to nginx"))
    }
}
