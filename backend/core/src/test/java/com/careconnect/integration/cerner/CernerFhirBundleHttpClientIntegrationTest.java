package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.integration.cerner.CernerFhirBundleHttpClient.ResourceType;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

/** Loopback integration coverage for the shared Condition/Encounter FHIR transport. */
class CernerFhirBundleHttpClientIntegrationTest {

    private HttpServer server;
    private ExecutorService executor;
    private CernerFhirBundleHttpClient client;
    private final AtomicInteger calls = new AtomicInteger();
    private volatile int status = 200;
    private volatile String body;
    private volatile String secondBody;
    private volatile long delayMillis;
    private volatile URI lastRequest;

    @BeforeEach
    void start() throws Exception {
        body = fixture("/cerner/fhir/condition/bundle-one-condition.json");
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        executor = Executors.newCachedThreadPool();
        server.setExecutor(executor);
        server.createContext("/fhir/", exchange -> {
            final int call = calls.incrementAndGet();
            lastRequest = exchange.getRequestURI();
            try {
                Thread.sleep(delayMillis);
                final String selected = call == 2 && secondBody != null ? secondBody : body;
                final byte[] bytes = selected.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().set("Content-Type", "application/fhir+json");
                exchange.sendResponseHeaders(status, bytes.length);
                exchange.getResponseBody().write(bytes);
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
            } finally {
                exchange.close();
            }
        });
        server.start();
        client = new CernerFhirBundleHttpClient(base(), Duration.ofMillis(300));
    }

    @AfterEach
    void stop() {
        server.stop(0);
        executor.shutdownNow();
    }

    @Test
    @Tag("M3-REQ-04")
    void retrievesConditionAndIgnoresUnrelatedMixedEntry() {
        body = body.replace("\"entry\": [", "\"entry\": [{\"resource\":"
                + "{\"resourceType\":\"Patient\",\"id\":\"included\"}},");

        final var result = client.getResources(
                ResourceType.CONDITION, "synthetic-patient-1", "token");

        assertThat(result.resources()).singleElement()
                .extracting(node -> node.path("id").asText())
                .isEqualTo("synthetic-condition-1");
    }

    @Test
    @Tag("M3-REQ-04")
    void emptyBundleIsSuccessful() {
        body = "{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"entry\":[]}";

        assertThat(client.getResources(ResourceType.ENCOUNTER, "synthetic-patient-1", "token")
                .resources()).isEmpty();
    }

    @Test
    @Tag("M3-REQ-08")
    void followsTrustedPaginationAndCombinesEncounterResources() throws Exception {
        final String next = base() + "Encounter?patient=synthetic-patient-1&page=2";
        body = fixture("/cerner/fhir/encounter/bundle-page-1-with-next-link.json")
                .replace("https://example.test/fhir/Encounter?patient=synthetic-patient-1"
                        + "&pageToken=synthetic-encounter-page-2", next);
        secondBody = fixture("/cerner/fhir/encounter/bundle-page-2.json");

        final var result = client.getResources(
                ResourceType.ENCOUNTER, "synthetic-patient-1", "token");

        assertThat(result.resources()).extracting(node -> node.path("id").asText())
                .containsExactly(
                        "synthetic-encounter-page-1-record",
                        "synthetic-encounter-page-2-record");
        assertThat(calls).hasValue(2);
    }

    @Test
    @Tag("M3-REQ-03")
    void rejectsUnsafePaginationHost() {
        body = "{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"link\":["
                + "{\"relation\":\"next\",\"url\":\"https://example.test/fhir/next\"}]}";

        assertSourceFailure(ResourceType.CONDITION, "CERNER_INVALID_RESPONSE", false);
        assertThat(calls).hasValue(1);
    }

    @Test
    @Tag("M3-REQ-06")
    void rejectsMalformedBodyAndWrongPatientResource() throws Exception {
        body = "{broken";
        assertSourceFailure(ResourceType.CONDITION, "CERNER_INVALID_RESPONSE", false);

        body = fixture("/cerner/fhir/condition/bundle-one-condition.json")
                .replace("Patient/synthetic-patient-1", "Patient/other");
        assertSourceFailure(ResourceType.CONDITION, "CERNER_INVALID_RESPONSE", false);
    }

    @Test
    @Tag("M3-REQ-07")
    void timeoutIsRetryableAndDoesNotLoop() {
        delayMillis = 1000;

        assertSourceFailure(ResourceType.CONDITION, "CERNER_TIMEOUT", true);
        assertThat(calls).hasValue(1);
    }

    @Test
    @Tag("M3-REQ-07")
    void rateLimitIsRetryableAndDoesNotLoop() {
        status = 429;

        assertSourceFailure(ResourceType.ENCOUNTER, "CERNER_UNAVAILABLE", true);
        assertThat(calls).hasValue(1);
    }

    @Test
    @Tag("M3-REQ-09")
    void unauthorizedIsReportedForServiceLevelRefresh() {
        status = 401;
        assertSourceFailure(ResourceType.CONDITION, "CERNER_AUTH_EXPIRED", false);
    }

    @Test
    @Tag("M3-REQ-01")
    void readsTrustedPatientDirectlyInsteadOfUsingPatientSearch() throws Exception {
        body = fixture("/cerner/fhir/patient/patient-complete.json");

        final var patient = client.getPatient("synthetic-patient-1", "token");

        assertThat(patient.path("id").asText()).isEqualTo("synthetic-patient-1");
        assertThat(lastRequest.getPath()).isEqualTo("/fhir/Patient/synthetic-patient-1");
        assertThat(lastRequest.getQuery()).isNull();
    }

    @Test
    @Tag("M3-REQ-05")
    void boundedAppointmentSearchIncludesProposedRecordWithoutTimes() throws Exception {
        body = fixture("/cerner/fhir/appointment/bundle-proposed-no-times.json");

        final var result = client.getAppointments(
                "synthetic-patient-1",
                "token",
                Instant.parse("2010-01-01T00:00:00Z"),
                Instant.parse("2027-01-01T00:00:00Z"));

        assertThat(result.resources()).singleElement()
                .extracting(resource -> resource.path("status").asText())
                .isEqualTo("proposed");
        assertThat(lastRequest.getRawQuery())
                .contains("patient=synthetic-patient-1")
                .contains("-date-or-req-period=ge2010-01-01T00%3A00%3A00Z")
                .contains("-date-or-req-period=lt2027-01-01T00%3A00%3A00Z");
    }

    @Test
    @Tag("M3-REQ-06")
    void rejectsAppointmentThatDoesNotContainTrustedPatientParticipant() throws Exception {
        body = fixture("/cerner/fhir/appointment/bundle-one-appointment.json")
                .replace("Patient/synthetic-patient-1", "Patient/other");

        assertThatThrownBy(() -> client.getAppointments(
                "synthetic-patient-1",
                "token",
                Instant.parse("2010-01-01T00:00:00Z"),
                Instant.parse("2027-01-01T00:00:00Z")))
                .isInstanceOf(CernerSourceException.class)
                .satisfies(error -> assertThat(((CernerSourceException) error).code())
                        .isEqualTo("CERNER_INVALID_RESPONSE"));
    }

    private void assertSourceFailure(
            final ResourceType type, final String code, final boolean retryable) {
        assertThatThrownBy(() -> client.getResources(type, "synthetic-patient-1", "token"))
                .isInstanceOf(CernerSourceException.class)
                .satisfies(error -> {
                    final CernerSourceException sourceError = (CernerSourceException) error;
                    assertThat(sourceError.code()).isEqualTo(code);
                    assertThat(sourceError.retryable()).isEqualTo(retryable);
                });
    }

    private String fixture(final String path) throws Exception {
        try (var input = getClass().getResourceAsStream(path)) {
            assertThat(input).isNotNull();
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private URI base() {
        return URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/fhir/");
    }
}
