package com.careconnect.integration.cerner;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/** Validates fixture shape and sanitization without defining the pending canonical mapping contract. */
class CernerFiveResourceFixtureStructureTest {
  private static final ObjectMapper JSON = new ObjectMapper();
  private static final List<String> NEW_FIXTURES = List.of(
      "/cerner/fhir/patient/patient-complete.json",
      "/cerner/fhir/patient/patient-missing-optional-fields.json",
      "/cerner/fhir/condition/bundle-one-condition.json",
      "/cerner/fhir/condition/bundle-empty.json",
      "/cerner/fhir/condition/bundle-missing-optional-fields.json",
      "/cerner/fhir/condition/bundle-entered-in-error.json",
      "/cerner/fhir/encounter/bundle-one-encounter.json",
      "/cerner/fhir/encounter/bundle-empty.json",
      "/cerner/fhir/encounter/bundle-missing-optional-fields.json",
      "/cerner/fhir/encounter/bundle-page-1-with-next-link.json",
      "/cerner/fhir/encounter/bundle-page-2.json",
      "/cerner/fhir/appointment/bundle-one-appointment.json",
      "/cerner/fhir/appointment/bundle-empty.json",
      "/cerner/fhir/appointment/bundle-proposed-no-times.json",
      "/cerner/fhir/appointment/bundle-page-1-with-next-link.json",
      "/cerner/fhir/appointment/bundle-page-2.json");

  @ParameterizedTest
  @Tag("M3-REQ-16")
  @CsvSource({
      "/cerner/fhir/patient/patient-complete.json,synthetic-patient-1",
      "/cerner/fhir/patient/patient-missing-optional-fields.json,synthetic-patient-minimal"
  })
  void patientFixturesHaveSyntheticIdentity(final String path, final String expectedId)
      throws IOException {
    final JsonNode patient = fixture(path);
    assertEquals("Patient", patient.path("resourceType").asText());
    assertEquals(expectedId, patient.path("id").asText());
  }

  @ParameterizedTest
  @Tag("M3-REQ-17")
  @Tag("M3-REQ-18")
  @Tag("M3-REQ-19")
  @CsvSource({
      "/cerner/fhir/condition/bundle-one-condition.json,Condition",
      "/cerner/fhir/condition/bundle-missing-optional-fields.json,Condition",
      "/cerner/fhir/condition/bundle-entered-in-error.json,Condition",
      "/cerner/fhir/encounter/bundle-one-encounter.json,Encounter",
      "/cerner/fhir/encounter/bundle-missing-optional-fields.json,Encounter",
      "/cerner/fhir/appointment/bundle-one-appointment.json,Appointment",
      "/cerner/fhir/appointment/bundle-proposed-no-times.json,Appointment"
  })
  void populatedBundlesContainTheExpectedResource(final String path, final String resourceType)
      throws IOException {
    final JsonNode bundle = fixture(path);
    assertEquals("Bundle", bundle.path("resourceType").asText());
    assertEquals("searchset", bundle.path("type").asText());
    assertEquals(1, bundle.path("entry").size());
    assertEquals(resourceType,
        bundle.path("entry").path(0).path("resource").path("resourceType").asText());
  }

  @ParameterizedTest
  @Tag("M3-REQ-17")
  @Tag("M3-REQ-18")
  @Tag("M3-REQ-19")
  @CsvSource({
      "/cerner/fhir/condition/bundle-empty.json",
      "/cerner/fhir/encounter/bundle-empty.json",
      "/cerner/fhir/appointment/bundle-empty.json"
  })
  void emptyBundlesAreValidSearchsets(final String path) throws IOException {
    final JsonNode bundle = fixture(path);
    assertEquals("Bundle", bundle.path("resourceType").asText());
    assertEquals("searchset", bundle.path("type").asText());
    assertTrue(bundle.path("entry").isArray());
    assertTrue(bundle.path("entry").isEmpty());
  }

  @Test
  @Tag("M3-REQ-19")
  void proposedAppointmentHasRequestedPeriodWithoutConfirmedTimes() throws IOException {
    final JsonNode appointment = fixture(
        "/cerner/fhir/appointment/bundle-proposed-no-times.json")
        .path("entry").path(0).path("resource");
    assertEquals("proposed", appointment.path("status").asText());
    assertFalse(appointment.has("start"));
    assertFalse(appointment.has("end"));
    assertEquals(1, appointment.path("requestedPeriod").size());
  }

  @ParameterizedTest
  @Tag("M3-REQ-08")
  @Tag("M3-REQ-18")
  @Tag("M3-REQ-19")
  @CsvSource({
      "/cerner/fhir/encounter/bundle-page-1-with-next-link.json,/cerner/fhir/encounter/bundle-page-2.json,Encounter",
      "/cerner/fhir/appointment/bundle-page-1-with-next-link.json,/cerner/fhir/appointment/bundle-page-2.json,Appointment"
  })
  void paginationFixturePairsUseNextOnlyOnFirstPage(
      final String firstPath, final String secondPath, final String resourceType)
      throws IOException {
    final JsonNode first = fixture(firstPath);
    final JsonNode second = fixture(secondPath);
    assertTrue(hasNextLink(first));
    assertFalse(hasNextLink(second));
    assertEquals(resourceType,
        first.path("entry").path(0).path("resource").path("resourceType").asText());
    assertEquals(resourceType,
        second.path("entry").path(0).path("resource").path("resourceType").asText());
    assertTrue(nextUrl(first).startsWith("https://example.test/fhir/"));
  }

  @Test
  @Tag("M3-REQ-06")
  void newFixtureBodiesContainNoSandboxHostOrTenant() throws IOException {
    for (final String path : NEW_FIXTURES) {
      final String body = fixtureText(path);
      assertFalse(body.contains("fhir-open.cerner.com"), path);
      assertFalse(body.contains("fhir-ehr-code.cerner.com"), path);
      assertFalse(body.contains("ec2458f2-1e24-41c8-b71b-0e701af7583d"), path);
      assertFalse(body.toLowerCase().contains("bearer "), path);
    }
  }

  private JsonNode fixture(final String path) throws IOException {
    return JSON.readTree(fixtureText(path));
  }

  private boolean hasNextLink(final JsonNode bundle) {
    return !nextUrl(bundle).isEmpty();
  }

  private String nextUrl(final JsonNode bundle) {
    for (final JsonNode link : bundle.path("link")) {
      if ("next".equals(link.path("relation").asText())) {
        return link.path("url").asText();
      }
    }
    return "";
  }

  private String fixtureText(final String path) throws IOException {
    try (var input = getClass().getResourceAsStream(path)) {
      assertNotNull(input, path);
      return new String(input.readAllBytes(), StandardCharsets.UTF_8);
    }
  }
}
