package com.careconnect.integration.cerner;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Real loopback HTTP tests using shared synthetic fixtures; no external service or database. */
class CernerAllergyHttpClientIntegrationTest {
    private HttpServer server;
    private ExecutorService executor;
    private CernerAllergyHttpClient client;
    private final AtomicInteger calls = new AtomicInteger();
    private volatile int upstream = 200;
    private volatile String body;
    private volatile byte[] rawBody;
    private volatile long delay;
    private volatile String query;
    private volatile String authorization;

    @BeforeEach
    void start() throws Exception {
        try (var input = getClass().getResourceAsStream("/cerner/fhir/allergyintolerance/bundle-one-active-confirmed-allergy.json")) {
            assertNotNull(input);
            body = new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        executor = Executors.newCachedThreadPool();
        server.setExecutor(executor);
        server.createContext("/fhir/AllergyIntolerance", exchange -> {
            calls.incrementAndGet();
            query = exchange.getRequestURI().getRawQuery();
            authorization = exchange.getRequestHeaders().getFirst("Authorization");
            try {
                Thread.sleep(delay);
                byte[] bytes = rawBody == null ? body.getBytes(StandardCharsets.UTF_8) : rawBody;
                exchange.getResponseHeaders().set("Content-Type", "application/fhir+json");
                exchange.getResponseHeaders().set("Location", "/fhir/AllergyIntolerance");
                exchange.sendResponseHeaders(upstream, bytes.length);
                exchange.getResponseBody().write(bytes);
            } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            finally { exchange.close(); }
        });
        server.start();
        client = new CernerAllergyHttpClient(URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/fhir/"), Duration.ofMillis(300));
    }

    @AfterEach
    void stop() { server.stop(0); executor.shutdownNow(); }

    @Test
    void mapsSharedFixtureAndSendsToken() {
        var result = client.getAllergies("synthetic-patient-1", "synthetic-token");
        assertEquals(1, result.size());
        assertEquals("synthetic-active-allergy", result.get(0).sourceRecordId());
        assertEquals("patient=synthetic-patient-1", query);
        assertEquals("Bearer synthetic-token", authorization);
    }

    @ParameterizedTest
    @CsvSource({"401,CERNER_AUTH_EXPIRED,false", "403,CERNER_ACCESS_DENIED,false", "429,CERNER_UNAVAILABLE,true", "500,CERNER_UNAVAILABLE,true", "503,CERNER_UNAVAILABLE,true", "302,CERNER_UNEXPECTED_RESPONSE,false", "404,CERNER_UNEXPECTED_RESPONSE,false"})
    void translatesFailuresWithoutRetryOrRedirect(int statusCode, String code, boolean retryable) {
        upstream = statusCode; body = "private details synthetic-token";
        var error = assertFailure(code, retryable);
        assertEquals("Cerner source error", error.getMessage());
        assertNull(error.getCause());
        assertEquals(1, calls.get());
    }

    @Test
    void timeoutDoesNotLoop() {
        delay = 1500;
        assertTimeoutPreemptively(Duration.ofSeconds(3), () -> assertFailure("CERNER_TIMEOUT", true));
        assertEquals(1, calls.get());
    }

    @Test
    void malformedJsonIsNotEmptySuccess() { body = "{private"; assertFailure("CERNER_INVALID_RESPONSE", false); }

    @Test
    void malformedUtf8Rejected() {
        // Invalid two-byte UTF-8 sequence in a clinical text field must not be replaced silently.
        rawBody = body.replace("aspirin", "PLACEHOLDER").getBytes(StandardCharsets.UTF_8);
        int position = new String(rawBody, StandardCharsets.UTF_8).indexOf("PLACEHOLDER");
        assertTrue(position >= 0);
        rawBody[position] = (byte) 0xc3;
        rawBody[position + 1] = (byte) 0x28;
        assertFailure("CERNER_INVALID_RESPONSE", false);
    }

    @Test
    void trailingJsonRejected() {
        body = "{\"resourceType\":\"Bundle\",\"type\":\"searchset\"} {}";
        assertFailure("CERNER_INVALID_RESPONSE", false);
    }

    @Test
    void disconnectedServerIsRetryable() {
        server.stop(0);
        assertFailure("CERNER_UNAVAILABLE", true);
        assertEquals(0, calls.get());
    }

    @Test
    void wrongPatientRejectsResponse() {
        var error = assertThrows(CernerSourceException.class, () -> client.getAllergies("other-patient", "synthetic-token"));
        assertEquals("CERNER_INVALID_RESPONSE", error.code());
    }

    @Test
    void oversizedResponseRejected() { body = " ".repeat(1_048_577); assertFailure("CERNER_INVALID_RESPONSE", false); }

    @Test
    void paginationExplicitlyBlocked() {
        body = "{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"link\":[{\"relation\":\"next\",\"url\":\"https://example.test/next\"}]}";
        assertFailure("CERNER_PAGINATION_UNSUPPORTED", false);
        assertEquals(1, calls.get());
    }

    @Test
    void emptySearchsetSucceeds() {
        body = "{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"entry\":[]}";
        assertTrue(client.getAllergies("synthetic-patient-1", "synthetic-token").isEmpty());
    }

    @Test
    void invalidBundleShapeRejected() {
        body = "{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"entry\":{}}";
        assertFailure("CERNER_INVALID_RESPONSE", false);
    }

    @Test
    void invalidInputsMakeNoRequest() {
        assertThrows(IllegalArgumentException.class, () -> client.getAllergies("../bad", "synthetic-token"));
        assertThrows(CernerSourceException.class, () -> client.getAllergies("synthetic-patient-1", ""));
        assertThrows(CernerSourceException.class, () -> client.getAllergies("synthetic-patient-1", "token\r\nheader"));
        assertEquals(0, calls.get());
    }

    @Test
    void remotePlainHttpRejected() {
        assertThrows(IllegalArgumentException.class, () -> new CernerAllergyHttpClient(URI.create("http://example.test/fhir/"), Duration.ofSeconds(1)));
    }

    @Test
    void httpFailureReachesControllerEnvelope() throws Exception {
        upstream = 401;
        // Test-only trusted link and access policy; actual app security is outside this test.
        var mvc = MockMvcBuilders.standaloneSetup(new CernerAllergyController(
                id -> client.getAllergies("synthetic-patient-1", "synthetic-token"), (name, id) -> true)).build();
        mvc.perform(get("/v1/api/cerner/patients/42/allergies").principal(() -> "synthetic-user"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CERNER_AUTH_EXPIRED"))
                .andExpect(jsonPath("$.message").value("Cerner source error"))
                .andExpect(jsonPath("$.retryable").value(false));
        assertEquals(1, calls.get());
    }

    private CernerSourceException assertFailure(String code, boolean retryable) {
        var error = assertThrows(CernerSourceException.class, () -> client.getAllergies("synthetic-patient-1", "synthetic-token"));
        assertEquals(code, error.code()); assertEquals(retryable, error.retryable()); return error;
    }
}
