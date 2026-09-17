package com.careconnect.service.cerner;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.net.URI;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class CernerResourceMapperTest {
  private final ObjectMapper json = new ObjectMapper();
  private final CernerResourceMapper mapper =
      new CernerResourceMapper(Clock.fixed(Instant.parse("2026-09-17T12:00:00Z"), ZoneOffset.UTC));
  private final CernerResourceMapper.PatientLink link =
      new CernerResourceMapper.PatientLink(
          7, URI.create("https://example.test/r4/tenant-one/"), "p1");

  private ObjectNode read(String text) throws Exception {
    return (ObjectNode) json.readTree(text);
  }

  private ObjectNode patient() throws Exception {
    return read("{\"resourceType\":\"Patient\",\"id\":\"p1\"}");
  }

  private ObjectNode appointment() throws Exception {
    return read(
        """
        {"resourceType":"Appointment","id":"a1","status":"booked",
         "start":"2026-09-19T09:00:00-04:00","end":"2026-09-19T10:00:00-04:00",
         "participant":[{"actor":{"reference":"Patient/p1"},"status":"accepted"}]}
        """);
  }

  @Test
  void selectsCurrentOfficialNameAndAllGivenParts() throws Exception {
    ObjectNode p = patient();
    p.set(
        "name",
        json.readTree(
            """
            [{"use":"old","given":["Old"]},{"use":"usual","given":["Usual"]},
             {"use":"official","given":["Future"],"period":{"start":"2030-01-01T00:00:00Z"}},
             {"use":"official","given":["Ada","Marie"],"family":"Example"}]
            """));
    var result = mapper.patient(p, link).fields();
    assertEquals("Ada Marie", result.at("/display/firstName").asText());
    assertEquals("Example", result.at("/display/lastName").asText());
    assertEquals(4, result.at("/source/name").size());
  }

  @Test
  void doesNotSplitFreeTextNameOrInventFamily() throws Exception {
    var p = patient();
    p.set("name", json.readTree("[{\"text\":\"Example Person\"}]"));
    assertTrue(mapper.patient(p, link).fields().path("display").isEmpty());
  }

  @ParameterizedTest
  @ValueSource(strings = {"1990", "1990-01", "1990-01-03"})
  void preservesBirthPrecision(String date) throws Exception {
    var p = patient();
    p.put("birthDate", date);
    p.put("gender", "unknown");
    var result = mapper.patient(p, link).fields();
    assertEquals(date, result.at("/source/birthDate").asText());
    assertEquals(
        date.length() == 4 ? "YEAR" : date.length() == 7 ? "MONTH" : "DAY",
        result.path("birthDatePrecision").asText());
    assertEquals("unknown", result.at("/source/gender").asText());
  }

  @ParameterizedTest
  @ValueSource(strings = {"1990-02-30", "1990-13", "birthday", "2026-1-1"})
  void rejectsBadBirthDate(String value) throws Exception {
    var p = patient();
    p.put("birthDate", value);
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(p, link));
  }

  @Test
  void isolatesTenantsAndKeepsOpaqueVersion() throws Exception {
    var p = patient();
    p.putObject("meta").put("versionId", "v-X").put("lastUpdated", "2026-09-01T03:00:00+03:00");
    var a = mapper.patient(p, link).fields();
    var b =
        mapper
            .patient(
                p,
                new CernerResourceMapper.PatientLink(
                    7, URI.create("https://example.test/r4/tenant-two"), "p1"))
            .fields();
    assertNotEquals(a.path("sourceKey"), b.path("sourceKey"));
    assertEquals("v-X", a.path("sourceVersion").asText());
    assertEquals("2026-09-01T00:00:00Z", a.path("sourceUpdatedAt").asText());
    assertEquals("2026-09-17T12:00:00Z", a.path("fetchedAt").asText());
  }

  @Test
  void patientCannotCrossLink() throws Exception {
    var p = patient();
    p.put("id", "p2");
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(p, link));
  }

  @Test
  void normalizesTimeWithoutReplacingDuration() throws Exception {
    var a = appointment();
    a.put("minutesDuration", 30);
    var mapped = mapper.appointment(a, link).fields();
    assertEquals("2026-09-19T13:00:00Z", mapped.path("startAt").asText());
    assertEquals(30, mapped.at("/source/minutesDuration").asInt());
  }

  @Test
  void acceptsOnlyExactSameBaseAbsolutePatient() throws Exception {
    var a = appointment();
    ((ObjectNode) a.at("/participant/0/actor"))
        .put("reference", "https://example.test/r4/tenant-one/Patient/p1");
    assertNotNull(mapper.appointment(a, link));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "Patient/p2",
        "https://evil.test/Patient/p1",
        "https://example.test/r4/tenant-two/Patient/p1",
        "Patient/p1?extra=1",
        "Patient/p1/_history/1",
        "#p1",
        ""
      })
  void rejectsUnsafePatientReferences(String reference) throws Exception {
    var a = appointment();
    ((ObjectNode) a.at("/participant/0/actor")).put("reference", reference);
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @Test
  void rejectsAdditionalDifferentPatient() throws Exception {
    var a = appointment();
    a.withArray("participant").addObject().putObject("actor").put("reference", "Patient/p2");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @Test
  void rejectsMissingPatient() throws Exception {
    var a = appointment();
    a.remove("participant");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @ParameterizedTest
  @ValueSource(strings = {"proposed", "cancelled", "waitlist"})
  void allowsUnscheduledStates(String status) throws Exception {
    var a = appointment();
    a.put("status", status);
    a.remove("start");
    a.remove("end");
    assertEquals(status, mapper.appointment(a, link).fields().at("/source/status").asText());
  }

  @Test
  void acceptedParticipantDoesNotOverrideCancellation() throws Exception {
    var a = appointment();
    a.put("status", "cancelled");
    assertEquals("cancelled", mapper.appointment(a, link).fields().at("/source/status").asText());
  }

  @Test
  void hidesEnteredInError() throws Exception {
    var a = appointment();
    a.put("status", "entered-in-error");
    assertTrue(mapper.appointment(a, link).fields().path("hiddenFromActiveList").asBoolean());
  }

  @Test
  void rejectsUnscheduledBookedVisit() throws Exception {
    var a = appointment();
    a.remove("start");
    a.remove("end");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @Test
  void rejectsOneSidedTimes() throws Exception {
    var a = appointment();
    a.remove("end");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @Test
  void rejectsReversedTimes() throws Exception {
    var a = appointment();
    a.put("end", "2026-09-19T08:00:00-04:00");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @Test
  void rejectsOffsetFreeTimeWithoutLeakingValue() throws Exception {
    var a = appointment();
    a.put("start", "PRIVATE bad value");
    var error = assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
    assertEquals("Invalid Cerner field: start", error.getMessage());
    assertNull(error.getCause());
  }

  @Test
  void preservesMultipleCodesAndSeparateNotesAndPartialCreated() throws Exception {
    var a = appointment();
    a.set(
        "serviceType",
        json.readTree("[{\"text\":\"Review\",\"coding\":[{\"code\":\"A\"},{\"code\":\"B\"}]}]"));
    a.put("comment", "internal");
    a.put("patientInstruction", "public");
    a.put("created", "2026-09");
    var out = mapper.appointment(a, link).fields();
    assertEquals(2, out.at("/source/serviceType/0/coding").size());
    assertEquals("internal", out.at("/source/comment").asText());
    assertEquals("public", out.at("/source/patientInstruction").asText());
    assertEquals("2026-09", out.at("/source/created").asText());
  }

  @Test
  void defensiveCopiesAndNoRawNarrative() throws Exception {
    var p = patient();
    p.put("photo", "excluded");
    p.putNull("address");
    p.putArray("telecom");
    var result = mapper.patient(p, link);
    p.put("id", "changed");
    var first = result.fields();
    first.put("externalId", "changed");
    assertEquals("p1", result.fields().path("externalId").asText());
    assertFalse(result.fields().path("source").has("photo"));
    assertFalse(result.fields().path("source").has("gender"));
    assertTrue(result.fields().at("/source/address").isNull());
    assertTrue(result.fields().at("/source/telecom").isArray());
    assertEquals("CernerProjection[redacted]", result.toString());
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "http://example.test/r4",
        "https://user@example.test/r4",
        "https://example.test/r4?token=x",
        "https://example.test/a/../r4"
      })
  void rejectsUnsafeBases(String base) {
    assertThrows(
        IllegalArgumentException.class,
        () -> new CernerResourceMapper.PatientLink(7, URI.create(base), "p1"));
  }

  @Test
  void repeatMappingHasStableIdentity() throws Exception {
    assertEquals(
        mapper.appointment(appointment(), link).fields(),
        mapper.appointment(appointment(), link).fields());
  }

  @Test
  void rejectsUnknownStatusAndInvalidDuration() throws Exception {
    var a = appointment();
    a.put("status", "invented");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
    a.put("status", "booked");
    a.put("minutesDuration", -1);
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @ParameterizedTest
  @ValueSource(strings = {".", ".."})
  void rejectsDotSegmentIds(String id) throws Exception {
    var a = appointment();
    a.put("id", id);
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
    assertThrows(
        IllegalArgumentException.class,
        () -> new CernerResourceMapper.PatientLink(7, URI.create("https://example.test/r4"), id));
  }

  @Test
  void rejectsUnsupportedModifiersAtAnyDepth() throws Exception {
    var a = appointment();
    ((ObjectNode) a.withArray("participant").get(0))
        .putArray("modifierExtension")
        .addObject()
        .put("url", "https://example.test/modifier");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
    var p = patient();
    p.putArray("modifierExtension").addObject().put("url", "https://example.test/modifier");
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(p, link));
  }

  @Test
  void rejectsUnsupportedImplicitRules() throws Exception {
    var p = patient();
    p.put("implicitRules", "https://example.test/rules");
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(p, link));
  }

  @Test
  void handlesNullLinksWithSafeError() throws Exception {
    var p = patient();
    var a = appointment();
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(p, null));
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, null));
  }

  @Test
  void rejectsMalformedContainers() throws Exception {
    var p = patient();
    p.putArray("name").add("not-an-object");
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(p, link));
    var a = appointment();
    a.withArray("participant").add("not-an-object");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @Test
  void rejectsZeroYearAndMissingSeconds() throws Exception {
    var p = patient();
    p.put("birthDate", "0000");
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(p, link));
    var a = appointment();
    a.put("start", "2026-09-19T09:00-04:00");
    assertThrows(IllegalArgumentException.class, () -> mapper.appointment(a, link));
  }

  @Test
  void rejectsDeepAndOversizedSourceData() throws Exception {
    var large = patient();
    large.put("gender", "x".repeat(100001));
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(large, link));
    var p = patient();
    ObjectNode child = p;
    for (int i = 0; i < 40; i++) {
      child = child.putObject("nested");
    }
    final var deep = p;
    assertThrows(IllegalArgumentException.class, () -> mapper.patient(deep, link));
  }

  @Test
  void linkStringDoesNotDisclosePatientId() {
    assertEquals("CernerPatientLink[redacted]", link.toString());
  }
}
