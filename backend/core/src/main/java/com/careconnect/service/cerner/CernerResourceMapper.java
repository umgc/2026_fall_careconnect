package com.careconnect.service.cerner;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.net.URI;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.Year;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/** Pure, read-only FHIR R4 projection. Call only after server-side patient access checks. */
public final class CernerResourceMapper {
  private static final Set<String> STATUSES =
      Set.of(
          "proposed",
          "pending",
          "booked",
          "arrived",
          "fulfilled",
          "cancelled",
          "noshow",
          "entered-in-error",
          "checked-in",
          "waitlist");
  private final Clock clock;

  public CernerResourceMapper(Clock clock) {
    this.clock = Objects.requireNonNull(clock);
  }

  /** A trusted crosswalk supplied by the backend, never constructed from client input alone. */
  public record PatientLink(long localPatientId, URI sourceBase, String externalPatientId) {
    /** Validates the trusted crosswalk and normalizes the source base. */
    public PatientLink {
      if (localPatientId <= 0) {
        throw invalid("link.localPatientId");
      }
      requireId(externalPatientId, "link.externalPatientId");
      if (sourceBase == null
          || !"https".equals(sourceBase.getScheme())
          || sourceBase.getHost() == null
          || sourceBase.getUserInfo() != null
          || sourceBase.getQuery() != null
          || sourceBase.getFragment() != null
          || !sourceBase.normalize().equals(sourceBase)) {
        throw invalid("link.sourceBase");
      }
      String base = sourceBase.toString();
      sourceBase = URI.create(base.endsWith("/") ? base : base + "/");
    }

    @Override
    public String toString() {
      return "CernerPatientLink[redacted]";
    }
  }

  /** Source fields contain PHI. Do not log or expose them as an API response. */
  public static final class Projection {
    private final ObjectNode fields;

    private Projection(ObjectNode fields) {
      this.fields = fields.deepCopy();
    }

    public ObjectNode fields() {
      return fields.deepCopy();
    }

    @Override
    public String toString() {
      return "CernerProjection[redacted]";
    }
  }

  /** Maps a Patient without changing the local patient or account. */
  public Projection patient(JsonNode resource, PatientLink link) {
    requireLink(link);
    String id = resourceId(resource, "Patient");
    if (!id.equals(link.externalPatientId())) {
      throw invalid("patient.linkMismatch");
    }
    ObjectNode out = envelope(resource, link, "Patient", id);
    copy(
        resource,
        out,
        "identifier",
        "name",
        "birthDate",
        "gender",
        "telecom",
        "address",
        "communication",
        "active",
        "deceasedBoolean",
        "deceasedDateTime",
        "link");
    ObjectNode display = out.putObject("display");
    JsonNode best = null;
    for (JsonNode name : array(resource, "name")) {
      if ("old".equals(text(name, "use")) || !current(name)) {
        continue;
      }
      if (best == null || nameRank(name) < nameRank(best)) {
        best = name;
      }
    }
    if (best != null) {
      List<String> given = new ArrayList<>();
      for (JsonNode part : array(best, "given")) {
        if (!part.isTextual()) {
          throw invalid("name.given");
        }
        given.add(part.textValue());
      }
      if (!given.isEmpty()) {
        display.put("firstName", String.join(" ", given));
      }
      put(display, "lastName", text(best, "family"));
    }
    String birth = text(resource, "birthDate");
    if (birth != null && birth.startsWith("0000")) {
      throw invalid("birthDate");
    }
    if (birth != null) {
      String precision = birthPrecision(birth);
      if (precision == null) {
        throw invalid("birthDate");
      }
      out.put("birthDatePrecision", precision);
    }

    return new Projection(out);
  }

  private static String birthPrecision(String birth) {
    try {
      if (birth.matches("[0-9]{4}")) {
        Year.parse(birth);
        return "YEAR";
      }
      if (birth.matches("[0-9]{4}-[0-9]{2}")) {
        YearMonth.parse(birth);
        return "MONTH";
      }
      if (birth.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}")) {
        LocalDate.parse(birth);
        return "DAY";
      }
    } catch (DateTimeParseException ex) {
      // Return only validity; parser exceptions contain source data and must not escape.
      return null;
    }
    return null;
  }

  /** Maps an Appointment only when it belongs to the trusted patient link. */
  public Projection appointment(JsonNode resource, PatientLink link) {
    requireLink(link);
    final String id = resourceId(resource, "Appointment");
    String status = text(resource, "status");
    if (status == null || !STATUSES.contains(status)) {
      throw invalid("appointment.status");
    }
    String expected = "Patient/" + link.externalPatientId();
    String absolute = link.sourceBase().resolve(expected).toString();
    boolean matched = false;
    for (JsonNode participant : array(resource, "participant")) {
      if (!participant.isObject()) {
        throw invalid("appointment.participant");
      }
      JsonNode actor = participant.path("actor");
      String ref = text(actor, "reference");
      if (expected.equals(ref) || absolute.equals(ref)) {
        matched = true;
      } else if (ref != null && (ref.startsWith("Patient/") || ref.contains("/Patient/"))) {
        throw invalid("appointment.patientMismatch");
      } else if ("Patient".equals(text(actor, "type"))) {
        throw invalid("appointment.patientMismatch");
      }
    }
    if (!matched) {
      throw invalid("appointment.patientMissing");
    }
    Instant start = instant(resource, "start");
    Instant end = instant(resource, "end");
    if ((start == null) != (end == null)) {
      throw invalid("appointment.timePair");
    }
    if (start == null && !Set.of("proposed", "cancelled", "waitlist").contains(status)) {
      throw invalid("appointment.timesRequired");
    }
    if (start != null && end.isBefore(start)) {
      throw invalid("appointment.timeOrder");
    }
    JsonNode duration = resource.get("minutesDuration");
    if (duration != null
        && !duration.isNull()
        && (!duration.isIntegralNumber()
            || !duration.canConvertToInt()
            || duration.intValue() <= 0)) {
      throw invalid("appointment.minutesDuration");
    }
    ObjectNode out = envelope(resource, link, "Appointment", id);
    copy(
        resource,
        out,
        "status",
        "minutesDuration",
        "participant",
        "serviceType",
        "specialty",
        "appointmentType",
        "reasonCode",
        "reasonReference",
        "description",
        "comment",
        "patientInstruction",
        "cancelationReason",
        "requestedPeriod",
        "created");
    if (start != null) {
      out.put("startAt", start.toString());
      out.put("endAt", end.toString());
    }
    out.put("hiddenFromActiveList", "entered-in-error".equals(status));
    return new Projection(out);
  }

  private ObjectNode envelope(JsonNode resource, PatientLink link, String type, String id) {
    ObjectNode out = JsonNodeFactory.instance.objectNode();
    out.put("localPatientId", link.localPatientId());
    out.put("sourceBase", link.sourceBase().toString());
    out.put("resourceType", type);
    out.put("externalId", id);
    out.put("externalPatientId", link.externalPatientId());
    out.put("sourceKey", link.sourceBase().resolve(type + "/" + id).toString());
    out.put("fetchedAt", clock.instant().toString());
    put(out, "sourceVersion", text(resource.path("meta"), "versionId"));
    Instant updated = instant(resource.path("meta"), "lastUpdated");
    if (updated != null) {
      out.put("sourceUpdatedAt", updated.toString());
    }
    return out;
  }

  private boolean current(JsonNode name) {
    // Partial or malformed periods are not safe evidence of a current name.
    try {
      Instant start = instant(name.path("period"), "start");
      Instant end = instant(name.path("period"), "end");
      return (start == null || !start.isAfter(clock.instant()))
          && (end == null || !end.isBefore(clock.instant()));
    } catch (IllegalArgumentException ex) {
      return false;
    }
  }

  private static int nameRank(JsonNode name) {
    return switch (Objects.toString(text(name, "use"), "")) {
      case "official" -> 0;
      case "usual" -> 1;
      default -> 2;
    };
  }

  private static String resourceId(JsonNode node, String type) {
    if (node == null || !node.isObject() || !type.equals(text(node, "resourceType"))) {
      throw invalid("resourceType");
    }
    validateTree(node, 0, new int[] {0});
    if (node.hasNonNull("implicitRules")) {
      throw invalid("implicitRules");
    }
    String id = text(node, "id");
    requireId(id, "id");
    return id;
  }

  private static void requireId(String id, String field) {
    if (id == null || ".".equals(id) || "..".equals(id) || !id.matches("[A-Za-z0-9\\-.]{1,64}")) {
      throw invalid(field);
    }
  }

  private static String text(JsonNode node, String field) {
    if (!node.isObject() && !node.isMissingNode() && !node.isNull()) {
      throw invalid(field);
    }
    JsonNode value = node.get(field);
    if (value == null || value.isNull()) {
      return null;
    }
    if (!value.isTextual()) {
      throw invalid(field);
    }
    return value.textValue();
  }

  private static Iterable<JsonNode> array(JsonNode node, String field) {
    if (!node.isObject() && !node.isMissingNode() && !node.isNull()) {
      throw invalid(field);
    }
    JsonNode value = node.get(field);
    if (value == null || value.isNull()) {
      return List.of();
    }
    if (!value.isArray()) {
      throw invalid(field);
    }
    return value;
  }

  private static Instant instant(JsonNode node, String field) {
    String raw = text(node, field);
    if (raw == null) {
      return null;
    }
    if (!raw.matches(
        "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
            + "(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})")) {
      throw invalid(field);
    }
    Instant parsed = parseInstant(raw);
    if (parsed == null) {
      throw invalid(field);
    }
    return parsed;
  }

  private static Instant parseInstant(String raw) {
    try {
      return OffsetDateTime.parse(raw).toInstant();
    } catch (DateTimeParseException ex) {
      // The caller emits a field-only error, without PHI-bearing parser details.
      return null;
    }
  }

  private static void copy(JsonNode in, ObjectNode out, String... fields) {
    ObjectNode source = out.putObject("source");
    for (String field : fields) {
      if (in.has(field)) {
        source.set(field, in.get(field).deepCopy());
      }
    }
  }

  private static void put(ObjectNode out, String field, String value) {
    if (value != null) {
      out.put(field, value);
    }
  }

  private static void requireLink(PatientLink link) {
    if (link == null) {
      throw invalid("link");
    }
  }

  // Bound traversal before copying. HTTP callers must also bound bytes before JSON parsing.
  private static void validateTree(JsonNode node, int depth, int[] count) {
    count[0]++;
    if (depth > 32 || count[0] > 10000) {
      throw invalid("resourceSize");
    }
    if (node.isTextual() && node.textValue().length() > 100000) {
      throw invalid("fieldSize");
    }
    if (node.isObject()) {
      JsonNode modifiers = node.get("modifierExtension");
      if (modifiers != null
          && !modifiers.isNull()
          && (!modifiers.isArray() || !modifiers.isEmpty())) {
        throw invalid("modifierExtension");
      }
    }
    for (JsonNode child : node) {
      validateTree(child, depth + 1, count);
    }
  }

  private static IllegalArgumentException invalid(String field) {
    // Never include source values or parser causes in errors.
    return new IllegalArgumentException("Invalid Cerner field: " + field);
  }
}
