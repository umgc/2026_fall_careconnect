package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class CernerFhirBundleHttpClientTest {

    @Test
    void resourceTypesUseExpectedFhirNames() {
        assertThat(CernerFhirBundleHttpClient.ResourceType.CONDITION.fhirName())
                .isEqualTo("Condition");
        assertThat(CernerFhirBundleHttpClient.ResourceType.ENCOUNTER.fhirName())
                .isEqualTo("Encounter");
        assertThat(CernerFhirBundleHttpClient.ResourceType.APPOINTMENT.fhirName())
                .isEqualTo("Appointment");
    }

    @Test
    void validatesBaseAndTimeoutBeforeNetworkUse() {
        assertThat(new CernerFhirBundleHttpClient(
                URI.create("https://example.test/fhir/"), Duration.ofSeconds(1))).isNotNull();
        assertThatThrownBy(() -> new CernerFhirBundleHttpClient(
                URI.create("http://example.test/fhir/"), Duration.ofSeconds(1)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CernerFhirBundleHttpClient(
                URI.create("https://example.test/fhir/"), Duration.ofSeconds(31)))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void resultDefensivelyCopiesInputResources() throws Exception {
        final var json = new ObjectMapper().readTree("{\"id\":\"one\"}");
        final List<com.fasterxml.jackson.databind.JsonNode> resources =
                new ArrayList<>(List.of(json));
        final var result = new CernerFhirBundleHttpClient.Result(resources);

        resources.clear();
        ((com.fasterxml.jackson.databind.node.ObjectNode) json).put("id", "changed");

        assertThat(result.resources()).singleElement()
                .extracting(node -> node.path("id").asText()).isEqualTo("one");
    }

    @Test
    void getAllergiesReturnsOnlyAllergyConditions() throws Exception {
        final String bundle = """
                {
                  "resourceType":"Bundle",
                  "type":"searchset",
                  "entry":[
                    {"resource":{"resourceType":"Condition","id":"allergy-1",
                      "subject":{"reference":"Patient/patient-1"},
                      "category":[{"text":"allergy"}]}},
                    {"resource":{"resourceType":"Condition","id":"problem-1",
                      "subject":{"reference":"Patient/patient-1"},
                      "category":[{"text":"problem-list-item"}]}}
                  ]
                }
                """;
        final HttpServer server = HttpServer.create(
                new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/fhir/Condition", exchange -> {
            final byte[] response = bundle.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/fhir+json");
            exchange.sendResponseHeaders(200, response.length);
            exchange.getResponseBody().write(response);
            exchange.close();
        });
        server.start();
        try {
            final URI base = URI.create("http://127.0.0.1:"
                    + server.getAddress().getPort() + "/fhir/");

            assertThat(new CernerFhirBundleHttpClient(base, Duration.ofSeconds(2))
                    .getAllergies("patient-1").path(0).path("id").asText())
                    .isEqualTo("allergy-1");
        } finally {
            server.stop(0);
        }
    }
}
