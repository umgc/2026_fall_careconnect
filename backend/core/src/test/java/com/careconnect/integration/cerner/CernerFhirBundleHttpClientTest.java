package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
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
}
