package com.careconnect.client.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.careconnect.config.AthenahealthProperties;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

/**
 * Unit tests for {@link AthenahealthApiClient} against a mocked HTTP server, no real network
 * calls.
 */
class AthenahealthApiClientTest {

    private static final String BASE_URL = "https://sandbox.athenahealth.test/fhir/r4";
    private static final String TOKEN_URL = "https://sandbox.athenahealth.test/oauth2/v1/token";

    private RestTemplate restTemplate;
    private MockRestServiceServer server;
    private AthenahealthApiClient client;

    @BeforeEach
    void setUp() {
        restTemplate = new RestTemplate();
        server = MockRestServiceServer.createServer(restTemplate);

        final AthenahealthProperties properties = new AthenahealthProperties();
        properties.getApi().setBaseUrl(BASE_URL);
        properties.getAuth().setTokenUrl(TOKEN_URL);
        properties.getAuth().setClientId("client-id");
        properties.getAuth().setClientSecret("client-secret");

        client = new AthenahealthApiClient(restTemplate, properties);
    }

    @Test
    void sourceCodeIsAthenahealth() {
        assertThat(client.sourceCode()).isEqualTo("ATHENAHEALTH");
    }

    @Test
    void fetchesATokenOnceAndReusesItAcrossCalls() {
        server.expect(requestTo(TOKEN_URL))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess(
                        "{\"access_token\":\"tok-1\",\"expires_in\":300}",
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(BASE_URL + "/Appointment?patient=ext-1"))
                .andExpect(method(HttpMethod.GET))
                .andExpect(header("Authorization", "Bearer tok-1"))
                .andRespond(withSuccess(bundleWithOneAppointment("appt-1"), MediaType.APPLICATION_JSON));
        server.expect(requestTo(BASE_URL + "/Appointment?patient=ext-1"))
                .andExpect(method(HttpMethod.GET))
                .andExpect(header("Authorization", "Bearer tok-1"))
                .andRespond(withSuccess(bundleWithOneAppointment("appt-2"), MediaType.APPLICATION_JSON));

        final List<JsonNode> first = client.fetchResources("Appointment", "ext-1");
        final List<JsonNode> second = client.fetchResources("Appointment", "ext-1");

        assertThat(first).hasSize(1);
        assertThat(first.get(0).get("id").asText()).isEqualTo("appt-1");
        assertThat(second).hasSize(1);
        assertThat(second.get(0).get("id").asText()).isEqualTo("appt-2");
        // A third, unexpected token request would fail server.verify() below — the only way
        // this passes is if the second fetch reused the cached token instead of re-authing.
        server.verify();
    }

    @Test
    void resourceTypeSelectsTheFhirEndpointPath() {
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(
                        "{\"access_token\":\"tok-1\",\"expires_in\":300}",
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(BASE_URL + "/Coverage?patient=ext-1"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess(
                        "{\"resourceType\":\"Bundle\",\"entry\":[{\"resource\":"
                                + "{\"resourceType\":\"Coverage\",\"id\":\"cov-1\"}}]}",
                        MediaType.APPLICATION_JSON));

        final List<JsonNode> resources = client.fetchResources("Coverage", "ext-1");

        assertThat(resources).hasSize(1);
        assertThat(resources.get(0).get("resourceType").asText()).isEqualTo("Coverage");
    }

    @Test
    void patientResourceTypeFetchesByDirectIdNotSearch() {
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(
                        "{\"access_token\":\"tok-1\",\"expires_in\":300}",
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(BASE_URL + "/Patient/ext-1"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess(
                        "{\"resourceType\":\"Patient\",\"id\":\"ext-1\"}", MediaType.APPLICATION_JSON));

        final List<JsonNode> resources = client.fetchResources("Patient", "ext-1");

        assertThat(resources).hasSize(1);
        assertThat(resources.get(0).get("id").asText()).isEqualTo("ext-1");
    }

    @Test
    void bundleWithNoEntriesReturnsAnEmptyList() {
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(
                        "{\"access_token\":\"tok-1\",\"expires_in\":300}",
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(BASE_URL + "/Appointment?patient=ext-1"))
                .andRespond(withSuccess(
                        "{\"resourceType\":\"Bundle\",\"total\":0}", MediaType.APPLICATION_JSON));

        assertThat(client.fetchResources("Appointment", "ext-1")).isEmpty();
    }

    @Test
    void missingAccessTokenFailsClosed() {
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess("{\"token_type\":\"Bearer\"}", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> client.fetchResources("Appointment", "ext-1"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("access_token");
    }

    private static String bundleWithOneAppointment(final String appointmentId) {
        return """
                {
                  "resourceType": "Bundle",
                  "entry": [
                    { "resource": { "resourceType": "Appointment", "id": "%s", "status": "booked" } }
                  ]
                }
                """.formatted(appointmentId);
    }
}
