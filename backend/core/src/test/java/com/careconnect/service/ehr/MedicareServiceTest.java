package com.careconnect.service.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import ca.uhn.fhir.rest.server.exceptions.BaseServerResponseException;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.CapabilityStatement;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.Enumerations;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Resource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.*;

/**
 * {@link MedicareService} against a local stand-in for the Blue Button v3 FHIR and revoke endpoints,
 * so no network or CMS credentials are needed. Covers retry with backoff (FR-MCR-23), keeping the
 * pages already retrieved when a later page fails, no retry for a rejected token (FR-MCR-09), entries
 * rather than the optional Bundle.total, and the token revoke request (Basic auth, sandbox host).
 * The retry and partial-result logic is ported from FHIRService in PR #223.
 */
class MedicareServiceTest {

    private static final FhirContext CTX = FhirContext.forR4();
    private static final String TOKEN = "test-token-not-a-secret";

    private HttpServer server;
    private String base;
    private MedicareService service;
    private final Map<String, Integer> hits = new ConcurrentHashMap<>();
    private final Map<String, Function<HttpExchange, Reply>> routes = new ConcurrentHashMap<>();
    private final List<Duration> waits = Collections.synchronizedList(new ArrayList<>());
    private final List<String> revokeAuth = Collections.synchronizedList(new ArrayList<>());
    private final List<String> revokeBody = Collections.synchronizedList(new ArrayList<>());

    private record Reply(int status, String body, Map<String, String> headers) {
        Reply(int status, String body) {
            this(status, body, Map.of());
        }
    }

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/fhir/", this::handle);
        server.createContext("/o/revoke", ex -> {
            revokeAuth.add(ex.getRequestHeaders().getFirst("Authorization"));
            revokeBody.add(new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            ex.sendResponseHeaders(200, -1);
            ex.close();
        });
        server.start();
        String root = "http://127.0.0.1:" + server.getAddress().getPort();
        base = root + "/fhir/";
        service = new MedicareService(base, root + "/o/revoke", waits::add);
        CapabilityStatement cs = new CapabilityStatement();
        cs.setFhirVersion(Enumerations.FHIRVersion._4_0_1);
        routes.put("metadata", ex -> new Reply(200, json(cs)));
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    private void handle(HttpExchange ex) throws IOException {
        String path = ex.getRequestURI().getPath().substring("/fhir/".length());
        String query = ex.getRequestURI().getRawQuery();
        String key = path + (query == null ? "" : "?" + query);
        if (!"metadata".equals(path)) {
            hits.merge(path, 1, Integer::sum);
            if (query != null) hits.merge(key, 1, Integer::sum);
        }
        Function<HttpExchange, Reply> route = routes.getOrDefault(key, routes.get(path));
        Reply r = route == null ? new Reply(404, "{}") : route.apply(ex);
        byte[] bytes = r.body().getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().add("Content-Type", "application/fhir+json");
        r.headers().forEach((k, v) -> ex.getResponseHeaders().add(k, v));
        ex.sendResponseHeaders(r.status(), bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }

    private static String json(Resource r) {
        return CTX.newJsonParser().encodeResourceToString(r);
    }

    private static Bundle page(List<? extends Resource> resources, Integer total, String next) {
        Bundle b = new Bundle();
        b.setType(Bundle.BundleType.SEARCHSET);
        if (total != null) b.setTotal(total);
        for (Resource r : resources) b.addEntry().setResource(r);
        if (next != null) b.addLink().setRelation(Bundle.LINK_NEXT).setUrl(next);
        return b;
    }

    private static Coverage coverage(String id) {
        Coverage c = new Coverage();
        c.setId(id);
        c.setStatus(Coverage.CoverageStatus.ACTIVE);
        return c;
    }

    private static ExplanationOfBenefit eob(String id) {
        ExplanationOfBenefit e = new ExplanationOfBenefit();
        e.setId(id);
        return e;
    }

    private static Patient patient(String id) {
        Patient p = new Patient();
        p.setId(id);
        return p;
    }

    /** Replies with each status in turn, then the body with 200. */
    private static Function<HttpExchange, Reply> failThen(String body, int... statuses) {
        AtomicInteger call = new AtomicInteger();
        return ex -> {
            int i = call.getAndIncrement();
            return i < statuses.length ? new Reply(statuses[i], "{}") : new Reply(200, body);
        };
    }

    @Test
    @DisplayName("Patient search returns the single patient")
    void patientSearch() {
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(patient("p1")), null, null))));
        assertEquals("p1", service.requestMedicarePatientInfo(TOKEN).getIdElement().getIdPart());
    }

    @Test
    @DisplayName("Patient search with no Bundle.total still finds the patient (total is optional)")
    void patientSearchWithoutTotal() {
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(patient("p1")), null, null))));
        assertNotNull(service.requestMedicarePatientInfo(TOKEN));
    }

    @Test
    @DisplayName("Patient search retries a 503 and succeeds on the third attempt, waiting 2 s then 4 s")
    void patientSearchRetries() {
        routes.put("Patient", failThen(json(page(List.of(patient("p1")), 1, null)), 503, 503));
        assertNotNull(service.requestMedicarePatientInfo(TOKEN));
        assertEquals(3, hits.get("Patient"));
        assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits);
    }

    @Test
    @DisplayName("A rate-limit response honours Retry-After")
    void retryAfterHonoured() {
        AtomicInteger call = new AtomicInteger();
        routes.put("Coverage", ex -> call.getAndIncrement() == 0
                ? new Reply(429, "{}", Map.of("Retry-After", "7"))
                : new Reply(200, json(page(List.of(coverage("c1")), 1, null))));
        assertEquals(1, service.requestMedicareCoverageInfo(TOKEN).size());
        assertEquals(List.of(Duration.ofSeconds(7)), waits);
    }

    @Test
    @DisplayName("After three failed attempts the error is thrown")
    void givesUpAfterThreeAttempts() {
        routes.put("Coverage", ex -> new Reply(500, "{}"));
        assertThrows(BaseServerResponseException.class, () -> service.requestMedicareCoverageInfo(TOKEN));
        assertEquals(3, hits.get("Coverage"));
    }

    @Test
    @DisplayName("A rejected token (401) is not retried")
    void unauthorizedNotRetried() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(401, "{}"));
        assertThrows(AuthenticationException.class, () -> service.requestMedicareEOBInfo(TOKEN));
        assertEquals(1, hits.get("ExplanationOfBenefit"));
        assertTrue(waits.isEmpty());
    }

    @Test
    @DisplayName("Follows next links across pages")
    void followsPages() {
        String next = base + "Coverage?page=2";
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(coverage("c1")), null, next))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(List.of(coverage("c2")), null, null))));
        List<Coverage> all = service.requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of("c1", "c2"), all.stream().map(c -> c.getIdElement().getIdPart()).toList());
    }

    @Test
    @DisplayName("An empty result is empty even without Bundle.total")
    void emptyWithoutTotal() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(List.of(), null, null))));
        assertTrue(service.requestMedicareEOBInfo(TOKEN).isEmpty());
    }

    @Test
    @DisplayName("If a later page fails, retrieveMedicareEOB keeps the pages that arrived")
    void partialResultKept() {
        String next = base + "ExplanationOfBenefit?page=2";
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(List.of(eob("e1"), eob("e2")), null, next))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(503, "{}"));

        BlueButtonRetrieval<ExplanationOfBenefit> r = service.retrieveMedicareEOB(TOKEN, null);
        assertEquals(2, r.records().size());
        assertEquals(1, r.pagesRetrieved());
        assertEquals(2, r.failedPage());
        assertEquals(503, r.failureStatus());
        assertEquals(3, hits.get("ExplanationOfBenefit?page=2"), "the failing page is retried first");

        // The List method keeps its old contract: it throws when retrieval is incomplete.
        assertThrows(BaseServerResponseException.class, () -> service.requestMedicareEOBInfo(TOKEN));
    }

    @Test
    @DisplayName("A token rejected on a later page is thrown, not returned as a partial result")
    void tokenRejectedMidRetrievalThrows() {
        String next = base + "Coverage?page=2";
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(coverage("c1")), null, next))));
        routes.put("Coverage?page=2", ex -> new Reply(401, "{}"));
        assertThrows(AuthenticationException.class, () -> service.retrieveMedicareCoverage(TOKEN, null));
    }

    @Test
    @DisplayName("A response of the wrong resource type is rejected and names the type searched for")
    void wrongResourceType() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(eob("e1")), 1, null))));
        RuntimeException e = assertThrows(RuntimeException.class, () -> service.requestMedicareCoverageInfo(TOKEN));
        assertTrue(e.getMessage().contains("Coverage"), e.getMessage());
    }

    @Test
    @DisplayName("revoke sends Base64 Basic auth and a form-encoded token to the revoke endpoint")
    void revokeUsesBasicAuth() {
        service.setClientCredentials("client-id", "client-secret");
        service.revoke("a+b/c=");
        String expected = "Basic " + Base64.getEncoder()
                .encodeToString("client-id:client-secret".getBytes(StandardCharsets.UTF_8));
        assertEquals(List.of(expected), revokeAuth);
        assertEquals(List.of("token=a%2Bb%2Fc%3D"), revokeBody);
    }

    @Test
    @DisplayName("The default endpoints are the Blue Button v3 sandbox, including revoke")
    void defaultEndpointsAreSandboxV3() {
        assertEquals("https://sandbox.bluebutton.cms.gov/v3/fhir/", MedicareService.SANDBOX_BASE);
        assertEquals("https://sandbox.bluebutton.cms.gov/v3/o/revoke", MedicareService.SANDBOX_REVOKE);
    }
}
