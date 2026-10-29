package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class CernerAllergyHttpClientTest {

    @Test
    void acceptsSecureRemoteAndLoopbackTestBases() {
        assertThat(new CernerAllergyHttpClient(
                URI.create("https://example.test/fhir/"), Duration.ofSeconds(1))).isNotNull();
        assertThat(new CernerAllergyHttpClient(
                URI.create("http://127.0.0.1:8080/fhir/"), Duration.ofSeconds(1))).isNotNull();
    }

    @Test
    void rejectsUnsafeBasesAndOutOfRangeTimeouts() {
        assertThatThrownBy(() -> new CernerAllergyHttpClient(
                URI.create("http://example.test/fhir/"), Duration.ofSeconds(1)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CernerAllergyHttpClient(
                URI.create("https://example.test/fhir"), Duration.ofSeconds(1)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CernerAllergyHttpClient(
                URI.create("https://example.test/fhir/"), Duration.ZERO))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void resultDefensivelyCopiesCollectionsAndJson() throws Exception {
        final var json = new ObjectMapper().readTree("{\"id\":\"one\"}");
        final List<com.fasterxml.jackson.databind.JsonNode> raw = new ArrayList<>(List.of(json));
        final var result = new CernerAllergyHttpClient.Result(List.of(), raw);

        raw.clear();
        ((com.fasterxml.jackson.databind.node.ObjectNode) json).put("id", "changed");

        assertThat(result.rawResources()).singleElement()
                .extracting(node -> node.path("id").asText()).isEqualTo("one");
        assertThatThrownBy(() -> result.rawResources().add(json))
                .isInstanceOf(UnsupportedOperationException.class);
    }
}
