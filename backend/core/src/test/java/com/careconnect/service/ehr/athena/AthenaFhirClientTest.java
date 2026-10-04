package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.service.ehr.EhrAuditService;
import com.careconnect.service.ehr.EhrSourceResolver;
import com.careconnect.testsupport.fixtures.AthenaPropertiesFixtures;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.JSON;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.ROMILDA_ID;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.bundle;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.bundleWithNext;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.captured;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.condition;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.outcomeEntry;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.romilda;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Unit tests for {@link AthenaFhirClient} against a {@link MockRestServiceServer}, so the outgoing
 * request can be asserted as well as the parsing. The cases are the athena behaviours seen in the
 * preview sandbox: practice on every search, outcome entries inside a 200, cursor paging, and a 403
 * for a scope the app does not hold.
 */
class AthenaFhirClientTest {

    private static final String BASE = AthenaPropertiesFixtures.FHIR_BASE_URL;
    private static final String PRACTICE = AthenaPropertiesFixtures.PRACTICE_ID;
    private static final String PREVIEW_BASE = "https://api.preview.platform.athenahealth.com/fhir/r4";
    private static final long USER_ID = 7L;
    private static final MediaType FHIR_JSON = MediaType.valueOf("application/fhir+json");

    private RestTemplate restTemplate;
    private MockRestServiceServer server;
    private AthenaTokenProvider tokens;
    private EhrAuditService audit;
    private PatientRepository patients;
    private EhrPatientCrosswalkRepository crosswalks;
    private EhrSourceResolver sources;
    private AthenaFhirClient client;

    @BeforeEach
    void setUp() {
        restTemplate = new RestTemplate();
        server = MockRestServiceServer.createServer(restTemplate);
        tokens = mock(AthenaTokenProvider.class);
        when(tokens.accessToken()).thenReturn("tok");
        audit = mock(EhrAuditService.class);
        patients = mock(PatientRepository.class);
        crosswalks = mock(EhrPatientCrosswalkRepository.class);
        sources = mock(EhrSourceResolver.class);
        client = clientFor(AthenaPropertiesFixtures.builder().build());
    }

    private AthenaFhirClient clientFor(final AthenaProperties cfg) {
        return new AthenaFhirClient(restTemplate, cfg, tokens, audit, patients, crosswalks, sources);
    }

    private static Map<String, String> params(final String... pairs) {
        final Map<String, String> map = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) {
            map.put(pairs[i], pairs[i + 1]);
        }
        return map;
    }

    @Test
    @DisplayName("search sends ah-practice, the bearer token and the caller's parameters")
    void searchSendsPracticeTokenAndParams() {
        // Arrange
        server.expect(requestTo(startsWith(BASE + "/Patient?")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(header("Authorization", "Bearer tok"))
                .andExpect(queryParam("ah-practice", PRACTICE))
                .andExpect(queryParam("family", "Smith"))
                .andExpect(queryParam("given", "Romilda"))
                .andRespond(withSuccess(bundle(romilda()), FHIR_JSON));

        // Act
        final AthenaFhirClient.SearchResult result =
                client.search(USER_ID, PRACTICE, "Patient", params("family", "Smith", "given", "Romilda"));

        // Assert
        assertEquals(1, result.resources().size());
        assertEquals(ROMILDA_ID, result.resources().get(0).path("id").asText());
        assertTrue(result.complete());
        server.verify();
        verify(audit).record(USER_ID, AthenaProperties.SOURCE_ATHENA, "ATHENA_SEARCH", "Patient", null,
                EhrAuditService.OUTCOME_OK);
    }

    @Test
    @DisplayName("follows the cursor in link[next] on the same host, using a captured sandbox page")
    void followsCursorPagingOnTheSameHost() throws Exception {
        // Arrange: the captured page holds 5 patients and a next link back to the preview host.
        final String firstPage = captured("Patient-searchset.json");
        final String nextUrl = JSON.readTree(firstPage).path("link").get(1).path("url").asText();
        client = clientFor(AthenaPropertiesFixtures.builder().fhirBaseUrl(PREVIEW_BASE).build());
        server.expect(requestTo(startsWith(PREVIEW_BASE + "/Patient?")))
                .andRespond(withSuccess(firstPage, MediaType.APPLICATION_JSON));
        server.expect(requestTo(nextUrl))
                .andRespond(withSuccess(bundle(romilda()), MediaType.APPLICATION_JSON));

        // Act
        final AthenaFhirClient.SearchResult result =
                client.search(USER_ID, PRACTICE, "Patient", params("family", "Testpatient"));

        // Assert
        assertEquals(6, result.resources().size());
        assertTrue(result.complete());
        server.verify();
    }

    @Test
    @DisplayName("outcome entries and _include'd resources are never returned as matches")
    void dropsOutcomeAndIncludedEntries() {
        // Arrange
        final var practitioner = JSON.createObjectNode().put("resourceType", "Practitioner").put("id", "pr-1");
        server.expect(requestTo(startsWith(BASE + "/Patient?")))
                .andRespond(withSuccess(bundle(romilda(), practitioner, outcomeEntry("information", "informational")),
                        MediaType.APPLICATION_JSON));

        // Act
        final List<JsonNode> found = client.search(USER_ID, PRACTICE, "Patient", params("family", "Smith")).resources();

        // Assert
        assertEquals(1, found.size());
        assertEquals("Patient", found.get(0).path("resourceType").asText());
    }

    @Test
    @DisplayName("a fatal outcome inside an HTTP 200 fails the search as REJECTED")
    void fatalOutcomeInsideA200IsRejected() {
        // Arrange: how athena answers an over-broad query.
        server.expect(requestTo(startsWith(BASE + "/Patient?")))
                .andRespond(withSuccess(bundle(outcomeEntry("fatal", "too-costly")), MediaType.APPLICATION_JSON));

        // Act
        final AthenaFhirException ex = assertThrows(AthenaFhirException.class,
                () -> client.search(USER_ID, PRACTICE, "Patient", params("family", "Smith")));

        // Assert
        assertEquals(AthenaFhirException.Kind.REJECTED, ex.getKind());
        verify(audit).record(USER_ID, AthenaProperties.SOURCE_ATHENA, "ATHENA_SEARCH", "Patient", null,
                EhrAuditService.OUTCOME_ERROR);
    }

    @Test
    @DisplayName("a next link to another host is refused before it is requested, so the token stays home")
    void nextLinkToAnotherHostIsRefused() {
        // Arrange: exactly one expectation. Following the link would be a second request and fail.
        server.expect(ExpectedCount.once(), requestTo(startsWith(BASE + "/Condition?")))
                .andRespond(withSuccess(bundleWithNext("https://elsewhere.example/fhir/r4/Condition?cursor=1",
                        condition("c-1", "active", "Asthma", "2024-01-01")), MediaType.APPLICATION_JSON));

        // Act
        final AthenaFhirException ex = assertThrows(AthenaFhirException.class,
                () -> client.search(USER_ID, PRACTICE, "Condition", params("patient", ROMILDA_ID)));

        // Assert: refused rather than treated as the last page, which a sync would prune against.
        assertEquals(AthenaFhirException.Kind.REJECTED, ex.getKind());
        server.verify();
    }

    @Test
    @DisplayName("paging stops at MAX_PAGES and reports the result as incomplete")
    void stopsAtMaxPagesAndReportsIncomplete() {
        // Arrange: every page points at another page.
        server.expect(ExpectedCount.times(AthenaFhirClient.MAX_PAGES), requestTo(startsWith(BASE + "/Condition")))
                .andRespond(withSuccess(bundleWithNext(BASE + "/Condition?cursor=again",
                        condition("c-1", "active", "Asthma", null)), MediaType.APPLICATION_JSON));

        // Act
        final AthenaFhirClient.SearchResult result =
                client.search(USER_ID, PRACTICE, "Condition", params("patient", ROMILDA_ID));

        // Assert
        assertFalse(result.complete());
        assertEquals(AthenaFhirClient.MAX_PAGES, result.resources().size());
        server.verify();
    }

    @Test
    @DisplayName("a 403 for a scope the app lacks is SCOPE_DENIED, using the captured sandbox body")
    void scopeDeniedIsClassified() {
        // Arrange
        server.expect(requestTo(startsWith(BASE + "/Condition?")))
                .andRespond(withStatus(HttpStatus.FORBIDDEN).contentType(MediaType.APPLICATION_JSON)
                        .body(captured("scope-denied-example.json")));

        // Act
        final AthenaFhirException ex = assertThrows(AthenaFhirException.class,
                () -> client.search(USER_ID, PRACTICE, "Condition", params("patient", ROMILDA_ID)));

        // Assert
        assertEquals(AthenaFhirException.Kind.SCOPE_DENIED, ex.getKind());
    }

    @ParameterizedTest
    @CsvSource({"400,REJECTED", "401,UNAVAILABLE", "403,SCOPE_DENIED", "404,REJECTED",
                "429,UNAVAILABLE", "500,UNAVAILABLE", "503,UNAVAILABLE"})
    @DisplayName("HTTP statuses map to what the caller should do")
    void statusesMapToKinds(final int status, final AthenaFhirException.Kind expected) {
        assertEquals(expected, AthenaFhirClient.kindFor(status));
    }

    @Test
    @DisplayName("a 5xx from athena surfaces as UNAVAILABLE")
    void serverErrorIsUnavailable() {
        // Arrange
        server.expect(requestTo(startsWith(BASE + "/Condition?")))
                .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));

        // Act / Assert
        final AthenaFhirException ex = assertThrows(AthenaFhirException.class,
                () -> client.search(USER_ID, PRACTICE, "Condition", params("patient", ROMILDA_ID)));
        assertEquals(AthenaFhirException.Kind.UNAVAILABLE, ex.getKind());
    }

    @Test
    @DisplayName("no token means UNAVAILABLE, and athena is never called")
    void noTokenIsUnavailableWithoutACall() {
        // Arrange: no expectations, so any request fails the test.
        when(tokens.accessToken()).thenThrow(new IllegalStateException("quota exceeded"));

        // Act
        final AthenaFhirException ex = assertThrows(AthenaFhirException.class,
                () -> client.search(USER_ID, PRACTICE, "Patient", params("family", "Smith")));

        // Assert
        assertEquals(AthenaFhirException.Kind.UNAVAILABLE, ex.getKind());
        server.verify();
    }

    @Test
    @DisplayName("user-entered values are percent-encoded, never expanded as URI template variables")
    void userEnteredValuesAreEncodedNotExpanded() {
        // Arrange: braces would be read as a template variable if values were encoded before build().
        server.expect(requestTo(containsString("given=J%7Bx%7D")))
                .andRespond(withSuccess(bundle(), MediaType.APPLICATION_JSON));

        // Act
        final AthenaFhirClient.SearchResult result =
                client.search(USER_ID, PRACTICE, "Patient", params("family", "Smith", "given", "J{x}"));

        // Assert
        assertTrue(result.resources().isEmpty());
        server.verify();
        verify(audit).record(USER_ID, AthenaProperties.SOURCE_ATHENA, "ATHENA_SEARCH", "Patient", null,
                EhrAuditService.OUTCOME_EMPTY);
    }

    @Test
    @DisplayName("read fetches one resource by id with the practice attached")
    void readFetchesById() {
        // Arrange
        server.expect(requestTo(BASE + "/Patient/" + ROMILDA_ID + "?ah-practice=" + PRACTICE))
                .andRespond(withSuccess(romilda().toString(), FHIR_JSON));

        // Act
        final JsonNode found = client.read(USER_ID, PRACTICE, "Patient", ROMILDA_ID);

        // Assert
        assertEquals(ROMILDA_ID, found.path("id").asText());
        verify(audit).record(USER_ID, AthenaProperties.SOURCE_ATHENA, "ATHENA_READ", "Patient", null,
                EhrAuditService.OUTCOME_OK);
    }

    @Test
    @DisplayName("a read that answers with a different resource type is REJECTED")
    void readOfTheWrongTypeIsRejected() {
        // Arrange
        server.expect(requestTo(startsWith(BASE + "/Patient/")))
                .andRespond(withSuccess(captured("scope-denied-example.json"), MediaType.APPLICATION_JSON));

        // Act
        final AthenaFhirException ex = assertThrows(AthenaFhirException.class,
                () -> client.read(USER_ID, PRACTICE, "Patient", ROMILDA_ID));

        // Assert
        assertEquals(AthenaFhirException.Kind.REJECTED, ex.getKind());
    }

    @Test
    @DisplayName("fetch adds the patient from the user's crosswalk link")
    void fetchAddsTheLinkedPatient() {
        // Arrange
        linkUserTo(ROMILDA_ID);
        server.expect(requestTo(startsWith(BASE + "/Condition?")))
                .andExpect(queryParam("patient", ROMILDA_ID))
                .andExpect(queryParam("ah-practice", PRACTICE))
                .andRespond(withSuccess(bundle(condition("c-1", "active", "Asthma", "2024-01-01")),
                        MediaType.APPLICATION_JSON));

        // Act
        final List<JsonNode> found = client.fetch(USER_ID, "Condition", Map.of());

        // Assert
        assertEquals(1, found.size());
        server.verify();
    }

    @Test
    @DisplayName("fetch for a user with no link fails before calling athena")
    void fetchWithoutALinkFails() {
        // Arrange: no expectations; the source is registered but the user has no patient profile.
        when(sources.idForCode(AthenaProperties.SOURCE_ATHENA)).thenReturn(9L);
        when(patients.findByUserId(USER_ID)).thenReturn(Optional.empty());

        // Act / Assert
        assertThrows(IllegalStateException.class, () -> client.fetch(USER_ID, "Condition", Map.of()));
        server.verify();
    }

    @Test
    @DisplayName("search sends whichever practice the caller names, not a fixed one")
    void searchUsesTheGivenPractice() {
        // Arrange
        server.expect(requestTo(startsWith(BASE + "/Patient?")))
                .andExpect(queryParam("ah-practice", "a-1.Practice-80000"))
                .andRespond(withSuccess(bundle(), MediaType.APPLICATION_JSON));

        // Act
        client.search(USER_ID, "a-1.Practice-80000", "Patient", params("family", "Smith"));

        // Assert
        server.verify();
    }

    @Test
    @DisplayName("a chart id's practice is read from the id, and only if that practice is configured")
    void practiceComesFromTheChartId() {
        // Arrange: two configured practices.
        client = clientFor(AthenaPropertiesFixtures.builder()
                .practiceIds("a-1.Practice-195900,a-1.Practice-80000").build());

        // Act / Assert
        assertEquals(Optional.of("a-1.Practice-195900"), client.practiceFor(ROMILDA_ID));
        assertEquals(Optional.of("a-1.Practice-80000"), client.practiceFor("a-80000.E-12"));
        assertEquals(Optional.empty(), client.practiceFor("a-31.E-12"), "a practice nobody configured");
        assertEquals(Optional.empty(), client.practiceFor("E-12"), "not an athena id");
        assertEquals(Optional.empty(), client.practiceFor(null));
    }

    @Test
    @DisplayName("fetch searches the linked chart's own practice")
    void fetchUsesTheChartsPractice() {
        // Arrange: the chart is in the second of two configured practices.
        client = clientFor(AthenaPropertiesFixtures.builder()
                .practiceIds("a-1.Practice-195900,a-1.Practice-80000").build());
        linkUserTo("a-80000.E-12");
        server.expect(requestTo(startsWith(BASE + "/Condition?")))
                .andExpect(queryParam("ah-practice", "a-1.Practice-80000"))
                .andExpect(queryParam("patient", "a-80000.E-12"))
                .andRespond(withSuccess(bundle(), MediaType.APPLICATION_JSON));

        // Act
        client.fetch(USER_ID, "Condition", Map.of());

        // Assert
        server.verify();
    }

    @Test
    @DisplayName("fetch refuses a linked chart outside the configured practices without calling athena")
    void fetchRefusesAnUnconfiguredPractice() {
        // Arrange: no expectations, so any request fails the test.
        linkUserTo("a-31.E-12");

        // Act / Assert
        assertThrows(IllegalStateException.class, () -> client.fetch(USER_ID, "Condition", Map.of()));
        server.verify();
    }

    @Test
    @DisplayName("$everything is not offered by athena")
    void everythingIsUnsupported() {
        assertThrows(UnsupportedOperationException.class, () -> client.everything(USER_ID));
    }

    @Test
    @DisplayName("the sourceCode matches the seeded ehr_source code")
    void sourceCodeMatchesTheCanonicalSeed() {
        assertEquals("ATHENAHEALTH", client.sourceCode());
    }

    private void linkUserTo(final String athenaPatientId) {
        when(sources.idForCode(AthenaProperties.SOURCE_ATHENA)).thenReturn(9L);
        when(patients.findByUserId(USER_ID)).thenReturn(Optional.of(Patient.builder().id(5L).build()));
        when(crosswalks.findByPatientIdAndSourceId(5L, 9L)).thenReturn(Optional.of(EhrPatientCrosswalk.builder()
                .patientId(5L).sourceId(9L).externalPatientId(athenaPatientId).build()));
    }
}
