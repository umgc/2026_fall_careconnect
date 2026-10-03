package com.careconnect.service;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import ca.uhn.fhir.rest.server.exceptions.BaseServerResponseException;
import ca.uhn.fhir.rest.server.exceptions.InternalErrorException;
import com.careconnect.controller.BluebuttonController;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.user.DefaultOAuth2User;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * WBS 3.6.4 Performance and reliability verification (M3), FHIR retrieval part.
 * Verifies {@link FHIRService} against WBS 6.2.35 (pagination, partial failure and
 * backoff) and SRS FR-MCR-13/14 (retrieval with the stored access token),
 * FR-MCR-23 (retry on rate limiting), NFR-DEG-02 (retry when Medicare is unavailable)
 * and FR-MCR-09 (no further call with a rejected token), using a local stand-in for
 * the Blue Button FHIR server, so no network or CMS credentials are needed. The
 * {@code /results} cases drive {@link BluebuttonController} over the same stand-in.
 *
 * <p>A test named {@code finding_*} pins behaviour that does NOT meet the requirement
 * yet: it passes so the build stays green, and names its defect (DEF-MCR-nn) in
 * docs/verification/3.6.4-fhir-retrieval-reliability.md. When the code is fixed, the
 * test is flipped to assert the requirement. DEF-MCR-01…05 are fixed, so none remain.
 *
 * <p>Test IDs (TC-MCR-FHIR-nnn) are the Software Test Plan's, §3.12.
 */
class FHIRServiceReliabilityVerificationTest {

    private static final FhirContext CTX = FhirContext.forR4();
    private static final String TOKEN = "test-token-not-a-secret";

    private HttpServer server;
    private String base;
    private final Map<String, Integer> hits = new ConcurrentHashMap<>();
    private final List<String> authHeaders = Collections.synchronizedList(new ArrayList<>());
    private final List<String> queries = Collections.synchronizedList(new ArrayList<>());
    /** path + "?" + query -> response; unmatched requests get 404. */
    private final Map<String, Function<HttpExchange, Reply>> routes = new ConcurrentHashMap<>();

    private record Reply(int status, String body, Map<String, String> headers) {
        Reply(int status, String body) {
            this(status, body, Map.of());
        }
    }

    /** Waits the retry policy asked for; recorded instead of slept, so retry tests run instantly. */
    private final List<Duration> waits = Collections.synchronizedList(new ArrayList<>());

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/fhir/", this::handle);
        server.start();
        base = "http://127.0.0.1:" + server.getAddress().getPort() + "/fhir/";
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
            authHeaders.add(ex.getRequestHeaders().getFirst("Authorization"));
            queries.add(query == null ? "" : java.net.URLDecoder.decode(query, StandardCharsets.UTF_8));
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

    /** A searchset page with the given resources, an optional total and an optional next link. */
    private static Bundle page(List<? extends Resource> resources, Integer total, String next) {
        Bundle b = new Bundle();
        b.setType(Bundle.BundleType.SEARCHSET);
        if (total != null) b.setTotal(total);
        for (Resource r : resources) b.addEntry().setResource(r);
        if (next != null) b.addLink().setRelation(Bundle.LINK_NEXT).setUrl(next);
        return b;
    }

    private static List<Coverage> coverages(String prefix, int n) {
        List<Coverage> out = new ArrayList<>();
        for (int i = 1; i <= n; i++) {
            Coverage c = new Coverage();
            c.setId(prefix + i);
            out.add(c);
        }
        return out;
    }

    private static List<ExplanationOfBenefit> eobs(String prefix, int n) {
        List<ExplanationOfBenefit> out = new ArrayList<>();
        for (int i = 1; i <= n; i++) {
            ExplanationOfBenefit e = new ExplanationOfBenefit();
            e.setId(prefix + i);
            out.add(e);
        }
        return out;
    }

    private FHIRService service() {
        return new FHIRService(base, waits::add);
    }

    /** Replies in order, repeating the last one: e.g. fail once, then succeed. */
    private static Function<HttpExchange, Reply> sequence(Reply... replies) {
        AtomicInteger next = new AtomicInteger();
        return ex -> replies[Math.min(next.getAndIncrement(), replies.length - 1)];
    }

    private static List<String> ids(List<? extends Resource> rs) {
        return rs.stream().map(r -> r.getIdElement().getIdPart()).collect(Collectors.toList());
    }

    private static String httpDate(ZonedDateTime at) {
        return DateTimeFormatter.RFC_1123_DATE_TIME.format(at);
    }

    /** Calls {@code /results} as a beneficiary signed in through Blue Button, with the real service. */
    private ResponseEntity<String> results() {
        OAuth2AuthorizedClient client = mock(OAuth2AuthorizedClient.class);
        when(client.getAccessToken()).thenReturn(new OAuth2AccessToken(OAuth2AccessToken.TokenType.BEARER,
                TOKEN, Instant.now(), Instant.now().plusSeconds(3600)));
        OAuth2AuthorizedClientService clients = mock(OAuth2AuthorizedClientService.class);
        doReturn(client).when(clients).loadAuthorizedClient("bluebutton", "bene-1");
        List<SimpleGrantedAuthority> roles = List.of(new SimpleGrantedAuthority("ROLE_USER"));
        OAuth2AuthenticationToken auth = new OAuth2AuthenticationToken(
                new DefaultOAuth2User(roles, Map.of("sub", "bene-1"), "sub"), roles, "bluebutton");
        return new BluebuttonController(service(), clients).results(auth);
    }

    private void routePatient() {
        Patient p = new Patient();
        p.setId("p1");
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(p), 1, null))));
    }

    // ---- Pagination (WBS 6.2.35; FR-MCR-13/14) -------------------------------------------------

    @Test
    @DisplayName("TC-MCR-FHIR-001 Coverage retrieval follows every next link across 3 pages with no duplicates")
    void coverageFollowsAllPages() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 5, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(coverages("d", 2), 5, base + "Coverage?page=3"))));
        routes.put("Coverage?page=3", ex -> new Reply(200, json(page(coverages("e", 1), 5, null))));

        List<Coverage> result = service().requestMedicareCoverageInfo(TOKEN);

        assertEquals(List.of("c1", "c2", "d1", "d2", "e1"), ids(result));
        assertEquals(3, hits.get("Coverage"), "one request per page");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-002 EOB retrieval follows every next link across 3 pages")
    void eobFollowsAllPages() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 3), 7, base + "ExplanationOfBenefit?page=2"))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(200, json(page(eobs("b", 3), 7, base + "ExplanationOfBenefit?page=3"))));
        routes.put("ExplanationOfBenefit?page=3", ex -> new Reply(200, json(page(eobs("c", 1), 7, null))));

        List<ExplanationOfBenefit> result = service().requestMedicareEOBInfo(TOKEN);

        assertEquals(7, result.size());
        assertEquals(7, result.stream().map(e -> e.getIdElement().getIdPart()).distinct().count(), "no duplicates");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-003 An empty search result returns an empty list, not an error")
    void emptyResultIsEmptyList() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(), 0, null))));
        assertTrue(service().requestMedicareCoverageInfo(TOKEN).isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-004 Every request carries the patient's bearer token")
    void bearerTokenOnEveryRequest() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 1), 2, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(coverages("d", 1), 2, null))));

        service().requestMedicareCoverageInfo(TOKEN);

        assertEquals(2, authHeaders.size());
        assertTrue(authHeaders.stream().allMatch(("Bearer " + TOKEN)::equals));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-005 An incremental sync sends _lastUpdated=ge<date>")
    void incrementalSyncSendsLastUpdated() {
        routes.put("Coverage", ex -> new Reply(200, json(page(List.of(), 0, null))));
        Date since = Date.from(Instant.parse("2026-09-01T00:00:00Z"));

        service().requestMedicareCoverageInfo(TOKEN, since);

        // The date is sent in the JVM's local offset, so compare the instant, not the text.
        String q = queries.get(0);
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("_lastUpdated=ge([^&]+)").matcher(q);
        assertTrue(m.find(), q);
        assertEquals(since.toInstant(), java.time.OffsetDateTime.parse(m.group(1)).toInstant(), q);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-006 Patient lookup returns the single Patient, and refuses zero or several")
    void patientLookup() {
        Patient p = new Patient();
        p.setId("p1");
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(p), 1, null))));
        assertEquals("p1", service().requestMedicarePatientInfo(TOKEN).getIdElement().getIdPart());

        Patient q = new Patient();
        q.setId("p2");
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(p, q), 2, null))));
        RuntimeException e = assertThrows(RuntimeException.class, () -> service().requestMedicarePatientInfo(TOKEN));
        assertTrue(e.getMessage().contains("quantity"), e.getMessage());

        routes.put("Patient", ex -> new Reply(200, json(page(List.of(), 0, null))));
        RuntimeException none = assertThrows(RuntimeException.class, () -> service().requestMedicarePatientInfo(TOKEN));
        assertTrue(none.getMessage().contains("quantity: 0"), none.getMessage());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-007 A wrong resource type in a Coverage search is rejected")
    void wrongResourceTypeRejected() {
        routes.put("Coverage", ex -> new Reply(200, json(page(eobs("x", 1), 1, null))));
        RuntimeException e = assertThrows(RuntimeException.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertTrue(e.getMessage().contains("Invalid Coverage response type: ExplanationOfBenefit"), e.getMessage());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-013 A rejected token (HTTP 401) is tried once and surfaces as an authentication failure")
    void rejectedTokenIsNotRetried() {
        // FR-MCR-09: no further Medicare call with a token Medicare rejected. This must still hold
        // once DEF-MCR-02 adds retries: only 429 and 5xx may be retried, never 401.
        routes.put("Coverage", ex -> new Reply(401, "{}"));
        assertThrows(AuthenticationException.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(1, hits.get("Coverage"), "exactly one attempt with the rejected token");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-015 The public constructor still targets the CMS Blue Button sandbox")
    void publicConstructorUsesSandbox() throws ReflectiveOperationException {
        // The package-private base-URL constructor is a test seam only; the bean Spring builds must
        // keep the sandbox URL.
        java.lang.reflect.Field f = FHIRService.class.getDeclaredField("bluebuttonBase");
        f.setAccessible(true);
        assertEquals("https://sandbox.bluebutton.cms.gov/v3/fhir/", f.get(new FHIRService()));
    }

    // ---- Partial failure and retry (WBS 6.2.35; FR-MCR-23): DEF-MCR-01 and DEF-MCR-02, fixed ------

    @Test
    @DisplayName("TC-MCR-FHIR-008 A failed later Coverage page keeps the pages already retrieved (DEF-MCR-01)")
    void failedLaterPageKeepsEarlierPages() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 4, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(500, "{}"));

        BlueButtonRetrieval<Coverage> result = service().retrieveMedicareCoverage(TOKEN, null);

        assertFalse(result.isComplete());
        assertEquals(List.of("c1", "c2"), ids(result.records()), "page 1's records are kept, not discarded");
        assertEquals(1, result.pagesRetrieved());
        assertEquals(2, result.failedPage(), "the caller can tell how far retrieval got");
        assertEquals(500, result.failureStatus());
        assertEquals(1 + BlueButtonRetryPolicy.MAX_ATTEMPTS, hits.get("Coverage"),
                "page 1 once, then page 2 tried the full number of times before giving up");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-014 A failed later EOB page keeps the pages already retrieved (DEF-MCR-01)")
    void failedLaterEobPageKeepsEarlierPages() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 2), 4, base + "ExplanationOfBenefit?page=2"))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(500, "{}"));

        BlueButtonRetrieval<ExplanationOfBenefit> result = service().retrieveMedicareEOB(TOKEN, null);

        assertFalse(result.isComplete());
        assertEquals(List.of("a1", "a2"), ids(result.records()));
        assertEquals(2, result.failedPage());
        assertEquals(500, result.failureStatus());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-009 HTTP 429 and 503 are tried 3 times with 2 s then 4 s backoff (DEF-MCR-02)")
    void rateLimitIsRetriedWithBackoff() {
        routes.put("Coverage", ex -> new Reply(429, "{}"));
        BaseServerResponseException rateLimited =
                assertThrows(BaseServerResponseException.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(429, rateLimited.getStatusCode());
        assertEquals(3, hits.get("Coverage"), "FR-MCR-23: up to 3 attempts");
        assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits, "exponential backoff from 2 s");

        hits.clear();
        waits.clear();
        routes.put("Coverage", ex -> new Reply(503, "{}"));
        BaseServerResponseException unavailable =
                assertThrows(BaseServerResponseException.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(503, unavailable.getStatusCode());
        assertEquals(3, hits.get("Coverage"));
        assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-016 The List methods still fail, rather than return a short list, when a later page fails")
    void listMethodStillThrowsOnPartialRetrieval() {
        // Callers that need the complete set keep the old contract; only retrieveMedicare* returns partial data.
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 4, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(500, "{}"));

        BaseServerResponseException e =
                assertThrows(BaseServerResponseException.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(500, e.getStatusCode());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-017 A request that fails once with 503 succeeds on the retry")
    void transientFailureRecoversOnRetry() {
        routes.put("Coverage", sequence(new Reply(503, "{}"),
                new Reply(200, json(page(coverages("c", 2), 2, null)))));

        List<Coverage> result = service().requestMedicareCoverageInfo(TOKEN);

        assertEquals(List.of("c1", "c2"), ids(result));
        assertEquals(2, hits.get("Coverage"));
        assertEquals(List.of(Duration.ofSeconds(2)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-018 A Retry-After header sets the wait instead of the default backoff")
    void retryAfterIsHonoured() {
        routes.put("Coverage", sequence(new Reply(429, "{}", Map.of("Retry-After", "7")),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));

        assertEquals(1, service().requestMedicareCoverageInfo(TOKEN).size());
        assertEquals(List.of(Duration.ofSeconds(7)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-019 A very long Retry-After is capped so a request thread is not held for minutes")
    void retryAfterIsCapped() {
        routes.put("Coverage", sequence(new Reply(429, "{}", Map.of("Retry-After", "600")),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));

        service().requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of(BlueButtonRetryPolicy.MAX_RETRY_AFTER), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-020 Other 4xx errors (404) are not retried")
    void notFoundIsNotRetried() {
        routes.put("Coverage", ex -> new Reply(404, "{}"));
        assertThrows(BaseServerResponseException.class, () -> service().requestMedicareCoverageInfo(TOKEN));
        assertEquals(1, hits.get("Coverage"));
        assertTrue(waits.isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-021 The Patient search is retried the same way")
    void patientSearchIsRetried() {
        Patient p = new Patient();
        p.setId("p1");
        routes.put("Patient", sequence(new Reply(503, "{}"), new Reply(200, json(page(List.of(p), 1, null)))));

        assertEquals("p1", service().requestMedicarePatientInfo(TOKEN).getIdElement().getIdPart());
        assertEquals(2, hits.get("Patient"));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-022 A retrieval with no failures reports itself complete")
    void completeRetrievalIsMarkedComplete() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 2), 3, base + "ExplanationOfBenefit?page=2"))));
        routes.put("ExplanationOfBenefit?page=2", ex -> new Reply(200, json(page(eobs("b", 1), 3, null))));

        BlueButtonRetrieval<ExplanationOfBenefit> result = service().retrieveMedicareEOB(TOKEN, null);

        assertTrue(result.isComplete());
        assertEquals(List.of("a1", "a2", "b1"), ids(result.records()));
        assertEquals(2, result.pagesRetrieved());
        assertNull(result.failedPage());
        assertTrue(waits.isEmpty());
    }

    // ---- Testing Lead additions, PR #223 review (2026-10-02) -------------------------------------

    @Test
    @DisplayName("TC-MCR-FHIR-023 Two rate-limit responses then success: exactly 3 requests and the records are returned")
    void rateLimitedTwiceThenSucceeds() {
        // Component-level form of AC-MCR-23-1 (SRS TC-21.9, which stays Blocked at screen level).
        routes.put("Coverage", sequence(new Reply(429, "{}"), new Reply(429, "{}"),
                new Reply(200, json(page(coverages("c", 2), 2, null)))));

        List<Coverage> result = service().requestMedicareCoverageInfo(TOKEN);

        assertEquals(List.of("c1", "c2"), ids(result));
        assertEquals(3, hits.get("Coverage"), "exactly 3 requests");
        assertEquals(List.of(Duration.ofSeconds(2), Duration.ofSeconds(4)), waits);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-024 A later page that fails once with 503 is retried and retrieval completes")
    void laterPageRecoversOnRetry() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 3, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", sequence(new Reply(503, "{}"),
                new Reply(200, json(page(coverages("d", 1), 3, null)))));

        BlueButtonRetrieval<Coverage> result = service().retrieveMedicareCoverage(TOKEN, null);

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

        assertEquals(1, service().requestMedicareCoverageInfo(TOKEN).size());
        assertEquals(1, waits.size());
        Duration wait = waits.get(0);
        // The date has whole-second precision and some time passes before it is read.
        assertTrue(wait.compareTo(Duration.ofSeconds(5)) > 0 && wait.compareTo(Duration.ofSeconds(10)) <= 0,
                "wait " + wait + " should be just under 10 s");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-026 An unreadable Retry-After falls back to the default backoff; a date already past means no wait")
    void unusableRetryAfterFallsBack() {
        routes.put("Coverage", sequence(new Reply(429, "{}", Map.of("Retry-After", "soon")),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));
        service().requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of(Duration.ofSeconds(2)), waits, "unreadable: default 2 s");

        waits.clear();
        String past = httpDate(ZonedDateTime.now(ZoneOffset.UTC).minusMinutes(5));
        routes.put("Coverage", sequence(new Reply(429, "{}", Map.of("Retry-After", past)),
                new Reply(200, json(page(coverages("c", 1), 1, null)))));
        service().requestMedicareCoverageInfo(TOKEN);
        assertEquals(List.of(Duration.ZERO), waits, "a date in the past: retry now, never a negative wait");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-027 A token rejected on a later page (HTTP 401) is an authentication failure, not a partial result (DEF-MCR-05)")
    void rejectedTokenOnLaterPageIsNotPartial() {
        // FR-MCR-09 / AC-MCR-09-2: once Medicare rejects the token nothing more may be asked with it,
        // so a 401 must not be returned as "incomplete" for the caller to carry on from.
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 4, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(401, "{}"));

        assertThrows(AuthenticationException.class, () -> service().retrieveMedicareCoverage(TOKEN, null));
        assertEquals(2, hits.get("Coverage"), "page 2 tried once with the rejected token");
        assertTrue(waits.isEmpty());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-028 A first page that still fails after retries is thrown, not reported as a partial result")
    void firstPageFailureIsThrown() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(429, "{}"));

        BaseServerResponseException e = assertThrows(BaseServerResponseException.class,
                () -> service().retrieveMedicareEOB(TOKEN, null));
        assertEquals(429, e.getStatusCode());
        assertEquals(3, hits.get("ExplanationOfBenefit"));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-029 /results reports counts, complete=true and an empty incomplete list when every page arrives")
    void resultsCompleteBody() throws Exception {
        routePatient();
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 3, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(200, json(page(coverages("d", 1), 3, null))));
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 2), 2, null))));

        ResponseEntity<String> response = results();

        assertEquals(200, response.getStatusCode().value());
        JsonNode body = new ObjectMapper().readTree(response.getBody());
        assertEquals("p1", body.get("patient").get("id").asText());
        assertEquals(3, body.get("coverageCount").asInt());
        assertEquals(2, body.get("eobCount").asInt());
        assertTrue(body.get("complete").asBoolean());
        assertEquals(0, body.get("incomplete").size());
    }

    @Test
    @DisplayName("TC-MCR-FHIR-030 /results names each incomplete resource in valid JSON, whichever one fails, without echoing the error text")
    void resultsIncompleteBody() throws Exception {
        String coverageFails = "Coverage", eobFails = "ExplanationOfBenefit";
        for (List<String> failing : List.of(List.of(coverageFails), List.of(eobFails), List.of(coverageFails, eobFails))) {
            routes.keySet().removeIf(k -> !"metadata".equals(k));
            hits.clear();
            routePatient();
            for (String resource : List.of(coverageFails, eobFails)) {
                List<? extends Resource> firstPage = resource.equals(coverageFails) ? coverages("c", 2) : eobs("a", 2);
                routes.put(resource, ex -> new Reply(200, json(page(firstPage, 4, base + resource + "?page=2"))));
                routes.put(resource + "?page=2", failing.contains(resource)
                        ? ex -> new Reply(500, "{}")
                        : ex -> new Reply(200, json(page(resource.equals(coverageFails) ? coverages("d", 2) : eobs("b", 2), 4, null))));
            }

            ResponseEntity<String> response = results();

            assertEquals(200, response.getStatusCode().value(), failing.toString());
            JsonNode body = new ObjectMapper().readTree(response.getBody());
            assertFalse(body.get("complete").asBoolean(), failing.toString());
            assertEquals(failing.contains(coverageFails) ? 2 : 4, body.get("coverageCount").asInt(), failing.toString());
            assertEquals(failing.contains(eobFails) ? 2 : 4, body.get("eobCount").asInt(), failing.toString());
            JsonNode incomplete = body.get("incomplete");
            assertEquals(failing.size(), incomplete.size(), failing.toString());
            for (int i = 0; i < failing.size(); i++) {
                JsonNode entry = incomplete.get(i);
                assertEquals(failing.get(i), entry.get("resource").asText());
                assertEquals(2, entry.get("retrieved").asInt());
                assertEquals(1, entry.get("pagesRetrieved").asInt());
                assertEquals(2, entry.get("failedPage").asInt());
                assertEquals(500, entry.get("status").asInt());
            }
            assertFalse(response.getBody().contains("Internal Server Error"), "the failure message is not echoed");
        }
    }

    @Test
    @DisplayName("TC-MCR-FHIR-031 /results makes no further Medicare call after the token is rejected mid-retrieval (DEF-MCR-05)")
    void resultsStopsAfterRejectedToken() {
        // AC-MCR-09-2: "no further Medicare API call is attempted with the rejected token".
        routePatient();
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 2), 4, base + "Coverage?page=2"))));
        routes.put("Coverage?page=2", ex -> new Reply(401, "{}"));
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 1), 1, null))));

        ResponseEntity<String> response = results();

        assertNull(hits.get("ExplanationOfBenefit"), "no ExplanationOfBenefit request with the rejected token");
        assertEquals(502, response.getStatusCode().value());
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

    // ---- DEF-MCR-03 fixed: Bundle.total is optional ------------------------------------------

    @Test
    @DisplayName("TC-MCR-FHIR-010 A Coverage page with entries but no Bundle.total returns its records")
    void missingTotalKeepsEntries() {
        routes.put("Coverage", ex -> new Reply(200, json(page(coverages("c", 3), null, null))));

        List<Coverage> result = service().requestMedicareCoverageInfo(TOKEN);

        assertEquals(List.of("c1", "c2", "c3"), ids(result));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-011 An EOB page with entries but no Bundle.total returns its records")
    void missingTotalKeepsEobEntries() {
        routes.put("ExplanationOfBenefit", ex -> new Reply(200, json(page(eobs("a", 2), null, null))));

        List<ExplanationOfBenefit> result = service().requestMedicareEOBInfo(TOKEN);

        assertEquals(List.of("a1", "a2"), ids(result));
    }

    @Test
    @DisplayName("TC-MCR-FHIR-012 A Patient bundle with one entry but no Bundle.total returns the Patient")
    void missingTotalReturnsPatient() {
        Patient p = new Patient();
        p.setId("p1");
        routes.put("Patient", ex -> new Reply(200, json(page(List.of(p), null, null))));

        assertEquals("p1", service().requestMedicarePatientInfo(TOKEN).getIdElement().getIdPart());
    }
}
