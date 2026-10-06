package com.careconnect.service.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import ca.uhn.fhir.rest.server.exceptions.BaseServerResponseException;
import ca.uhn.fhir.rest.server.exceptions.InternalErrorException;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.CapabilityStatement;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.Enumerations;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.OperationOutcome;
import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Resource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.*;

/**
 * {@link MedicareService} against a local stand-in for the Blue Button v3 FHIR and revoke endpoints,
 * so no network or CMS credentials are needed. Covers retry with backoff (FR-MCR-23), keeping the
 * pages already retrieved when a later page fails, no retry for a rejected token (FR-MCR-09), entries
 * rather than the optional Bundle.total, and the token revoke request (Basic auth, sandbox host).
 * The retry and partial-result logic is ported from FHIRService in PR #223.
 * <p>
 * Test IDs TC-MCR-FHIR-001…035 are permanent (Software Test Plan §3.12). They were first run
 * against FHIRService, which #252 removed, and run here against MedicareService; 029…031 tested
 * BluebuttonController's /results, which #252 also removed. The revoke case is TC-MCR-LINK-031
 * (§3.18). Never renumber, never reuse.
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
    private final List<String> authHeaders = Collections.synchronizedList(new ArrayList<>());
    private final List<String> queries = Collections.synchronizedList(new ArrayList<>());

    private record Reply(int status, String body, Map<String, String> headers) {
        Reply(int status, String body) {
            this(status, body, Map.of());
        }
    }

    /** A reply that closes the connection without sending a response, as a dropped connection does. */
    private static final Reply DROP = new Reply(-1, "");

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
            authHeaders.add(ex.getRequestHeaders().getFirst("Authorization"));
            queries.add(query == null ? "" : URLDecoder.decode(query, StandardCharsets.UTF_8));
        }
        Function<HttpExchange, Reply> route = routes.getOrDefault(key, routes.get(path));
        Reply r = route == null ? new Reply(404, "{}") : route.apply(ex);
        if (r == DROP) {
            ex.close();
            return;
        }
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

    private static List<Coverage> coverages(String prefix, int n) {
        List<Coverage> out = new ArrayList<>();
        for (int i = 1; i <= n; i++) out.add(coverage(prefix + i));
        return out;
    }

    private static List<ExplanationOfBenefit> eobs(String prefix, int n) {
        List<ExplanationOfBenefit> out = new ArrayList<>();
        for (int i = 1; i <= n; i++) out.add(eob(prefix + i));
        return out;
    }

    private static List<String> ids(List<? extends Resource> rs) {
        return rs.stream().map(r -> r.getIdElement().getIdPart()).toList();
    }

    /** Replies in order, repeating the last one: e.g. fail once, then succeed. */
    private static Function<HttpExchange, Reply> sequence(Reply... replies) {
        AtomicInteger next = new AtomicInteger();
        return ex -> replies[Math.min(next.getAndIncrement(), replies.length - 1)];
    }

    private static String httpDate(ZonedDateTime at) {
        return DateTimeFormatter.RFC_1123_DATE_TIME.format(at);
    }

    private static OperationOutcome warning() {
        OperationOutcome warning = new OperationOutcome();
        warning.addIssue().setSeverity(OperationOutcome.IssueSeverity.WARNING)
                .setCode(OperationOutcome.IssueType.INFORMATIONAL);
        return warning;
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
    @DisplayName("TC-MCR-FHIR-006 Patient lookup returns the single Patient, and refuses zero or several")
    void patientSearch() {
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(patient("p1")), 1, null))));
        assertEquals("p1", service.requestMedicarePatientInfo(TOKEN).getIdElement().getIdPart());

        routes.put("Patient", ex -> new Reply(200, json(page(List.of(patient("p1"), patient("p2")), 2, null))));
        RuntimeException several = assertThrows(RuntimeException.class, () -> service.requestMedicarePatientInfo(TOKEN));
        assertTrue(several.getMessage().contains("quantity: 2"), several.getMessage());

        routes.put("Patient", ex -> new Reply(200, json(page(List.of(), 0, null))));
        RuntimeException none = assertThrows(RuntimeException.class, () -> service.requestMedicarePatientInfo(TOKEN));
        assertTrue(none.getMessage().contains("quantity: 0"), none.getMessage());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-012 A Patient bundle with one entry but no Bundle.total returns the Patient (DEF-MCR-03)")
    void patientSearchWithoutTotal() {
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(patient("p1")), null, null))));
        assertEquals("p1", service.requestMedicarePatientInfo(TOKEN).getIdElement().getIdPart());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-021 The Patient search is retried the same way: two 503s, then success after 2 s and 4 s")
    void patientSearchRetries() {
        routes.put("Patient", failThen(json(page(List.of(patient("p1")), 1, null)), 503, 503));
        assertNotNull(service.requestMedicarePatientInfo(TOKEN));
        assertEquals(3, hits.get("Patient"));
        assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-018 A Retry-After of 7 seconds sets the wait instead of the default backoff")
    void retryAfterHonoured() {
        AtomicInteger call = new AtomicInteger();
        routes.put("Coverage", ex -> call.getAndIncrement() == 0
                ? new Reply(429, "{}", Map.of("Retry-After", "7"))
                : new Reply(200, json(page(List.of(coverage("c1")), 1, null))));
        assertEquals(1, service.requestMedicareCoverageInfo(TOKEN).size());
        assertEquals(List.of(Duration.ofSeconds(7)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-028 A first page that still fails after retries is thrown, not reported as a partial result")
    void givesUpAfterThreeAttempts() {
        routes.put("Coverage", ex -> new Reply(500, "{}"));
        assertThrows(BaseServerResponseException.class, () -> service.requestMedicareCoverageInfo(TOKEN));
        assertEquals(3, hits.get("Coverage"));

        routes.put("ExplanationOfBenefit", ex -> new Reply(429, "{}"));
        BaseServerResponseException e = assertThrows(BaseServerResponseException.class,
                () -> service.retrieveMedicareEOB(TOKEN, null));
        assertEquals(429, e.getStatusCode());
        assertEquals(3, hits.get("ExplanationOfBenefit"));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-034 A dropped connection is tried 3 times in all, not again inside each attempt by the HTTP client (DEF-MCR-06)")
    void droppedConnectionIsTriedThreeTimesInAll() {
        routes.put("Coverage", ex -> DROP);

        assertThrows(BaseServerResponseException.class, () -> service.requestMedicareCoverageInfo(TOKEN));

        assertEquals(3, hits.get("Coverage"), "NFR-DEG-02: up to 3 attempts");
        assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-013 A rejected token (HTTP 401) is tried once and surfaces as an authentication failure")
    void unauthorizedNotRetried() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(401, "{}"));
        assertThrows(AuthenticationException.class, () -> service.requestMedicareEOBInfo(TOKEN));
        assertEquals(1, hits.get("ExplanationOfBenefit"));
        assertTrue(waits.isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-001 Coverage retrieval follows every next link across 3 pages, with no duplicates and one request per page")
    void followsPages() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(coverage("c1")), null, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(coverages("d", 2), null, base + "Coverage?page=3"))));
        routes.put("Coverage?page=3", ex -> new Reply(200, json(page(List.of(coverage("e1")), null, null))));
        List<Coverage> all = service.requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of("c1", "d1", "d2", "e1"), ids(all));
        assertEquals(3, hits.get("Coverage"), "one request per page");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-003 An empty search result returns an empty list, not an error, even without Bundle.total")
    void emptyWithoutTotal() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(List.of(), null, null))));
        assertTrue(service.requestMedicareEOBInfo(TOKEN).isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-014 A failed later EOB page keeps the pages already retrieved and reports the failed page and its status (DEF-MCR-01)")
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
        assertFalse(r.isComplete());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-016 The List methods still throw, rather than return a short list, when a later page fails")
    void listMethodStillThrowsOnPartialRetrieval() {
        // Split from TC-MCR-FHIR-014: callers that need the complete set keep the old contract.
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("e", 2), null, base + "ExplanationOfBenefit?page=2"))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(503, "{}"));
        BaseServerResponseException e =
                assertThrows(BaseServerResponseException.class, () -> service.requestMedicareEOBInfo(TOKEN));
        assertEquals(503, e.getStatusCode());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-027 A token rejected on a later page (HTTP 401) is an authentication failure, not a partial result (DEF-MCR-05)")
    void tokenRejectedMidRetrievalThrows() {
        String next = base + "Coverage?page=2";
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(coverage("c1")), null, next))));
        routes.put("Coverage?page=2", ex -> new Reply(401, "{}"));
        assertThrows(AuthenticationException.class, () -> service.retrieveMedicareCoverage(TOKEN, null));
        assertEquals(2, hits.get("Coverage"), "page 2 tried once with the rejected token");
        assertTrue(waits.isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-007 A wrong resource type in a Coverage search is rejected and names the type searched for")
    void wrongResourceType() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(eob("e1")), 1, null))));
        RuntimeException e = assertThrows(RuntimeException.class, () -> service.requestMedicareCoverageInfo(TOKEN));
        assertTrue(e.getMessage().contains("Coverage"), e.getMessage());
    }

    @Test
    @DisplayName("TC-MCR-LINK-031: revoke sends Base64 Basic auth and a form-encoded token to the revoke endpoint")
    void revokeUsesBasicAuth() {
        service.setClientCredentials("client-id", "client-secret");
        service.revoke("a+b/c=");
        String expected = "Basic " + Base64.getEncoder()
                .encodeToString("client-id:client-secret".getBytes(StandardCharsets.UTF_8));
        assertEquals(List.of(expected), revokeAuth);
        assertEquals(List.of("token=a%2Bb%2Fc%3D"), revokeBody);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-015 The public constructor Spring uses targets the Blue Button v3 sandbox, including revoke")
    void defaultEndpointsAreSandboxV3() throws ReflectiveOperationException {
        assertEquals("https://sandbox.bluebutton.cms.gov/v3/fhir/", MedicareService.SANDBOX_BASE);
        assertEquals("https://sandbox.bluebutton.cms.gov/v3/o/revoke", MedicareService.SANDBOX_REVOKE);
        // The base-URL constructor is a test seam only; the bean Spring builds must keep the sandbox.
        MedicareService bean = new MedicareService();
        for (String field : List.of("bluebuttonBase", "bluebuttonRevoke")) {
            java.lang.reflect.Field f = MedicareService.class.getDeclaredField(field);
            f.setAccessible(true);
            assertTrue(((String) f.get(bean)).startsWith("https://sandbox.bluebutton.cms.gov/v3/"), field);
        }
    }

    @Test
    @DisplayName("TC-MCR-FHIR-033 An OperationOutcome entry on a later page is skipped, and the records of every page are returned")
    void unexpectedEntryOnLaterPageIsSkipped() {
        String next = base + "Coverage?page=2";
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(coverage("c1")), null, next))));
        org.hl7.fhir.r4.model.OperationOutcome warning = new org.hl7.fhir.r4.model.OperationOutcome();
        warning.addIssue().setSeverity(org.hl7.fhir.r4.model.OperationOutcome.IssueSeverity.WARNING)
                .setCode(org.hl7.fhir.r4.model.OperationOutcome.IssueType.INFORMATIONAL);
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(List.of(coverage("c2"), warning), null, null))));
        List<Coverage> all = service.requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of("c1", "c2"), all.stream().map(c -> c.getIdElement().getIdPart()).toList());
    }

    // ---- Ported from FHIRServiceReliabilityVerificationTest (PR #223, closed unmerged) -------------
    // Testing Lead, 2026-10-06: the §3.12 cases that #237 did not carry into MedicareService.

    @Test
    @DisplayName("TC-MCR-FHIR-002 ExplanationOfBenefit retrieval follows every next link across 3 pages")
    void eobFollowsAllPages() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 3), 7, base + "ExplanationOfBenefit?page=2"))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(200, json(page(eobs("b", 3), 7, base + "ExplanationOfBenefit?page=3"))));
        routes.put("ExplanationOfBenefit?page=3", ex -> new Reply(200, json(page(eobs("c", 1), 7, null))));

        List<ExplanationOfBenefit> result = service.requestMedicareEOBInfo(TOKEN);

        assertEquals(7, result.size());
        assertEquals(7, ids(result).stream().distinct().count(), "no duplicates");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-004 Every request, follow-up pages included, carries the patient's bearer token")
    void bearerTokenOnEveryRequest() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 1), 2, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(coverages("d", 1), 2, null))));

        service.requestMedicareCoverageInfo(TOKEN);

        assertEquals(2, authHeaders.size());
        assertTrue(authHeaders.stream().allMatch(("Bearer " + TOKEN)::equals), authHeaders.toString());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-005 An incremental retrieval sends _lastUpdated=ge for the requested instant")
    void incrementalRetrievalSendsLastUpdated() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(), 0, null))));
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(List.of(), 0, null))));
        Date since = Date.from(Instant.parse("2026-09-01T00:00:00Z"));

        service.requestMedicareCoverageInfo(TOKEN, since);
        service.requestMedicareEOBInfo(TOKEN, since);

        // The date is sent in the JVM's local offset, so compare the instant, not the text.
        assertEquals(2, queries.size());
        for (String q : queries) {
            Matcher m = Pattern.compile("_lastUpdated=ge([^&]+)").matcher(q);
            assertTrue(m.find(), q);
            assertEquals(since.toInstant(), OffsetDateTime.parse(m.group(1)).toInstant(), q);
        }
    }

    @Test
    @DisplayName("TC-MCR-FHIR-008 A failed later Coverage page keeps the pages already retrieved and reports the failed page and its status (DEF-MCR-01)")
    void failedLaterCoveragePageKeepsEarlierPages() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 4, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(500, "{}"));

        BlueButtonRetrieval<Coverage> result = service.retrieveMedicareCoverage(TOKEN, null);

        assertFalse(result.isComplete());
        assertEquals(List.of("c1", "c2"), ids(result.records()), "page 1's records are kept, not discarded");
        assertEquals(1, result.pagesRetrieved());
        assertEquals(2, result.failedPage());
        assertEquals(500, result.failureStatus());
        assertEquals(1 + BlueButtonRetryPolicy.MAX_ATTEMPTS, hits.get("Coverage"),
                "page 1 once, then page 2 the full number of attempts");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-009 HTTP 429 and 503 are attempted three times, waiting 2 s then 4 s (DEF-MCR-02)")
    void rateLimitAndUnavailableAreRetriedWithBackoff() {
        for (int status : new int[] {429, 503}) {
            hits.clear();
            waits.clear();
            routes.put("Coverage", ex -> new Reply(status, "{}"));
            BaseServerResponseException e =
                    assertThrows(BaseServerResponseException.class, () -> service.requestMedicareCoverageInfo(TOKEN));
            assertEquals(status, e.getStatusCode());
            assertEquals(3, hits.get("Coverage"), "FR-MCR-23: up to 3 attempts");
            assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits, "backoff from 2 s");
        }
    }

    @Test
    @DisplayName("TC-MCR-FHIR-010 A Coverage page with entries but no Bundle.total returns its records (DEF-MCR-03)")
    void coverageWithoutTotalKeepsEntries() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 3), null, null))));
        assertEquals(List.of("c1", "c2", "c3"), ids(service.requestMedicareCoverageInfo(TOKEN)));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-011 An ExplanationOfBenefit page with entries but no Bundle.total returns its records (DEF-MCR-03)")
    void eobWithoutTotalKeepsEntries() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 2), null, null))));
        assertEquals(List.of("a1", "a2"), ids(service.requestMedicareEOBInfo(TOKEN)));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-017 A request that fails once with 503 succeeds on the retry after one 2 s wait")
    void transientFailureRecoversOnRetry() {
        routes.put("Coverage", sequence(new Reply(503, "{}"), new Reply(200, json(page(coverages("c", 2), 2, null)))));

        assertEquals(List.of("c1", "c2"), ids(service.requestMedicareCoverageInfo(TOKEN)));
        assertEquals(2, hits.get("Coverage"));
        assertEquals(List.of(Duration.ofSeconds(2)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-019 A Retry-After longer than 30 seconds is capped at 30 seconds")
    void retryAfterIsCapped() {
        routes.put("Coverage", sequence(new Reply(429, "{}", Map.of("Retry-After", "600")),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));

        service.requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of(Duration.ofSeconds(30)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-020 Another 4xx (404) is attempted once, with no wait")
    void notFoundIsNotRetried() {
        routes.put("Coverage", ex -> new Reply(404, "{}"));
        assertThrows(BaseServerResponseException.class, () -> service.requestMedicareCoverageInfo(TOKEN));
        assertEquals(1, hits.get("Coverage"));
        assertTrue(waits.isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-022 A retrieval with no failures reports itself complete, with no waits")
    void completeRetrievalIsMarkedComplete() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 2), 3, base + "ExplanationOfBenefit?page=2"))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(200, json(page(eobs("b", 1), 3, null))));

        BlueButtonRetrieval<ExplanationOfBenefit> result = service.retrieveMedicareEOB(TOKEN, null);

        assertTrue(result.isComplete());
        assertEquals(List.of("a1", "a2", "b1"), ids(result.records()));
        assertEquals(2, result.pagesRetrieved());
        assertNull(result.failedPage());
        assertTrue(waits.isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-023 Two rate-limit responses then success: exactly three requests, the records returned, waits of 2 s then 4 s")
    void rateLimitedTwiceThenSucceeds() {
        routes.put("Coverage", sequence(new Reply(429, "{}"), new Reply(429, "{}"),
                new Reply(200, json(page(coverages("c", 2), 2, null)))));

        assertEquals(List.of("c1", "c2"), ids(service.requestMedicareCoverageInfo(TOKEN)));
        assertEquals(3, hits.get("Coverage"), "exactly 3 requests");
        assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-024 A later page that fails once with 503 is retried and the retrieval completes")
    void laterPageRecoversOnRetry() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 3, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", sequence(new Reply(503, "{}"), new Reply(200, json(page(coverages("d", 1), 3, null)))));

        BlueButtonRetrieval<Coverage> result = service.retrieveMedicareCoverage(TOKEN, null);

        assertTrue(result.isComplete());
        assertEquals(List.of("c1", "c2", "d1"), ids(result.records()));
        assertEquals(2, result.pagesRetrieved());
        assertEquals(3, hits.get("Coverage"), "page 1 once, page 2 twice");
        assertEquals(List.of(Duration.ofSeconds(2)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-025 A Retry-After given as an HTTP date sets the wait until that time")
    void retryAfterHttpDateIsHonoured() {
        String in10s = httpDate(ZonedDateTime.now(ZoneOffset.UTC).plusSeconds(10));
        routes.put("Coverage", sequence(new Reply(503, "{}", Map.of("Retry-After", in10s)),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));

        assertEquals(1, service.requestMedicareCoverageInfo(TOKEN).size());
        assertEquals(1, waits.size());
        Duration wait = waits.get(0);
        // The date has whole-second precision and some time passes before it is read.
        assertTrue(wait.compareTo(Duration.ofSeconds(5)) > 0 && wait.compareTo(Duration.ofSeconds(10)) <= 0,
                "wait " + wait + " should be just under 10 s");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-026 An unreadable Retry-After falls back to the 2 s backoff, and a date already past means no wait")
    void unusableRetryAfterFallsBack() {
        routes.put("Coverage", sequence(new Reply(429, "{}", Map.of("Retry-After", "soon")),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));
        service.requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of(Duration.ofSeconds(2)), waits, "unreadable: default 2 s");

        waits.clear();
        String past = httpDate(ZonedDateTime.now(ZoneOffset.UTC).minusMinutes(5));
        routes.put("Coverage", sequence(new Reply(429, "{}", Map.of("Retry-After", past)),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));
        service.requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of(Duration.ZERO), waits, "a date in the past: retry now, never a negative wait");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-032 An interrupt during the backoff wait gives up with the original failure and keeps the interrupt")
    void interruptDuringBackoffGivesUp() {
        BlueButtonRetryPolicy policy = new BlueButtonRetryPolicy(d -> {
            throw new InterruptedException("shutdown");
        });
        InternalErrorException failure = new InternalErrorException("HTTP 500");
        AtomicInteger attempts = new AtomicInteger();

        try {
            BaseServerResponseException thrown = assertThrows(BaseServerResponseException.class,
                    () -> policy.execute("Coverage search", () -> {
                        attempts.incrementAndGet();
                        throw failure;
                    }, () -> null));
            assertSame(failure, thrown);
            assertEquals(1, attempts.get(), "no attempt after the interrupt");
            assertTrue(Thread.currentThread().isInterrupted(), "interrupt status is kept");
        } finally {
            Thread.interrupted(); // clear it so later tests are unaffected
        }
    }

    @Test
    @DisplayName("TC-MCR-FHIR-035 An OperationOutcome listed first on page 1 is skipped when the page also has records")
    void unexpectedFirstEntryOnFirstPageIsSkipped() {
        List<Resource> mixed = new ArrayList<>();
        mixed.add(warning());
        mixed.addAll(coverages("c", 2));
        routes.put("Coverage", ex -> new Reply(200, json(page(mixed, null, null))));

        assertEquals(List.of("c1", "c2"), ids(service.requestMedicareCoverageInfo(TOKEN)));
    }
}
