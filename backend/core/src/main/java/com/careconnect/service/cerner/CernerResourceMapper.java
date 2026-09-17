package com.careconnect.service.cerner;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.net.URI;
import java.text.ParsePosition;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.time.format.ResolverStyle;
import java.time.temporal.ChronoField;
import java.time.temporal.TemporalAccessor;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.StreamSupport;

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
  private static final String BIRTH_DATE = "birthDate";
  private static final String OLD_NAME = "old";
  private static final Set<String> DOT_SEGMENTS = Set.of(".", "..");
  private final Clock clock;

  public CernerResourceMapper(final Clock clock) {
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
      final String base = sourceBase.toString();
      sourceBase = URI.create(base.endsWith("/") ? base : base + "/");
    }

    @Override
    public String toString() {
      return "CernerPatientLink[redacted]";
    }
  }

  /** Source fields contain PHI. Do not log or expose them as an API response. */
  public static final class Projection {
    private final ObjectNode projectionData;

    private Projection(final ObjectNode fields) {
      this.projectionData = fields.deepCopy();
    }

    public ObjectNode fields() {
      return projectionData.deepCopy();
    }

    @Override
    public String toString() {
      return "CernerProjection[redacted]";
    }
  }

  /** Maps a Patient without changing the local patient or account. */
  public Projection patient(final JsonNode resource, final PatientLink link) {
    requireLink(link);
    final String logicalId = resourceId(resource, "Patient");
    if (!logicalId.equals(link.externalPatientId())) {
      throw invalid("patient.linkMismatch");
    }
    final ObjectNode projectionNode = envelope(resource, link, "Patient", logicalId);
    copy(
        resource,
        projectionNode,
        "identifier",
        "name",
        BIRTH_DATE,
        "gender",
        "telecom",
        "address",
        "communication",
        "active",
        "deceasedBoolean",
        "deceasedDateTime",
        "link");

    JsonNode best = null;
    for (final JsonNode name : array(resource, "name")) {
      if (OLD_NAME.equals(text(name, "use")) || !current(name)) {
        continue;
      }
      if (best == null || nameRank(name) < nameRank(best)) {
        best = name;
      }
    }
    mapDisplayName(projectionNode.putObject("display"), best);
    final String birth = text(resource, BIRTH_DATE);
    if (birth != null) {
      final String precision = birthPrecision(birth);
      if (precision.isEmpty() || birth.startsWith("0000")) {
        throw invalid(BIRTH_DATE);
      }
      projectionNode.put("birthDatePrecision", precision);
    }
    return new Projection(projectionNode);
  }

  private static void mapDisplayName(final ObjectNode display, final JsonNode best) {
    if (best != null) {
      final List<String> given =
          StreamSupport.stream(array(best, "given").spliterator(), false)
              .map(CernerResourceMapper::givenPart)
              .toList();
      if (!given.isEmpty()) {
        display.put("firstName", String.join(" ", given));
      }
      put(display, "lastName", text(best, "family"));
    }
  }

  private static String givenPart(final JsonNode part) {
    if (!part.isTextual()) {
      throw invalid("name.given");
    }
    return part.textValue();
  }

  private static String birthPrecision(final String birth) {
    final String pattern =
        Map.of(4, "uuuu", 7, "uuuu-MM", 10, "uuuu-MM-dd").getOrDefault(birth.length(), "");
    final String precision =
        Map.of(4, "YEAR", 7, "MONTH", 10, "DAY").getOrDefault(birth.length(), "");
    return !birth.matches("[0-9]{4}(-[0-9]{2}){0,2}")
            || pattern.isEmpty()
            || parseTemporal(
                    birth,
                    new DateTimeFormatterBuilder()
                        .appendPattern(pattern)
                        .parseDefaulting(ChronoField.MONTH_OF_YEAR, 1)
                        .parseDefaulting(ChronoField.DAY_OF_MONTH, 1)
                        .toFormatter()
                        .withResolverStyle(ResolverStyle.STRICT))
                == null
        ? ""
        : precision;
  }

  /** Maps an Appointment only when it belongs to the trusted patient link. */
  public Projection appointment(final JsonNode resource, final PatientLink link) {
    requireLink(link);
    final String logicalId = resourceId(resource, "Appointment");
    return mapAppointment(resource, link, logicalId);
  }

  private Projection mapAppointment(
      final JsonNode resource, final PatientLink link, final String logicalId) {
    final String status = text(resource, "status");
    if (status == null || !STATUSES.contains(status)) {
      throw invalid("appointment.status");
    }
    requirePatientParticipants(resource, link);
    final Instant start = instant(resource, "start");
    final Instant end = instant(resource, "end");
    if ((start == null) != (end == null)) {
      throw invalid("appointment.timePair");
    }
    if (start == null && !Set.of("proposed", "cancelled", "waitlist").contains(status)) {
      throw invalid("appointment.timesRequired");
    }
    if (start != null && end.isBefore(start)) {
      throw invalid("appointment.timeOrder");
    }
    final JsonNode duration = resource.get("minutesDuration");
    if (duration != null
        && !duration.isNull()
        && (!duration.isIntegralNumber()
            || !duration.canConvertToInt()
            || duration.intValue() <= 0)) {
      throw invalid("appointment.minutesDuration");
    }
    final ObjectNode projectionNode = envelope(resource, link, "Appointment", logicalId);
    copy(
        resource,
        projectionNode,
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
      projectionNode.put("startAt", start.toString());
      projectionNode.put("endAt", end.toString());
    }
    projectionNode.put("hiddenFromActiveList", "entered-in-error".equals(status));
    return new Projection(projectionNode);
  }

  private static void requirePatientParticipants(final JsonNode resource, final PatientLink link) {
    // Materialize all results so a later mismatched patient is never skipped.
    final List<Boolean> matches =
        StreamSupport.stream(array(resource, "participant").spliterator(), false)
            .map(participant -> matchesPatient(participant, link))
            .toList();
    if (!matches.contains(true)) {
      throw invalid("appointment.patientMissing");
    }
  }

  private static boolean matchesPatient(final JsonNode participant, final PatientLink link) {
    if (!participant.isObject()) {
      throw invalid("appointment.participant");
    }
    final JsonNode actor = participant.path("actor");
    final String ref = text(actor, "reference");
    final String expected = "Patient/" + link.externalPatientId();
    final boolean matched =
        expected.equals(ref) || link.sourceBase().resolve(expected).toString().equals(ref);
    if (!matched
        && (ref != null && (ref.startsWith("Patient/") || ref.contains("/Patient/"))
            || "Patient".equals(text(actor, "type")))) {
      throw invalid("appointment.patientMismatch");
    }
    return matched;
  }

  private ObjectNode envelope(
      final JsonNode resource, final PatientLink link, final String type, final String logicalId) {
    final ObjectNode projectionNode = JsonNodeFactory.instance.objectNode();
    projectionNode.put("localPatientId", link.localPatientId());
    projectionNode.put("sourceBase", link.sourceBase().toString());
    projectionNode.put("resourceType", type);
    projectionNode.put("externalId", logicalId);
    projectionNode.put("externalPatientId", link.externalPatientId());
    projectionNode.put("sourceKey", link.sourceBase().resolve(type + "/" + logicalId).toString());
    projectionNode.put("fetchedAt", clock.instant().toString());
    put(projectionNode, "sourceVersion", text(resource.path("meta"), "versionId"));
    final Instant updated = instant(resource.path("meta"), "lastUpdated");
    if (updated != null) {
      projectionNode.put("sourceUpdatedAt", updated.toString());
    }
    return projectionNode;
  }

  private boolean current(final JsonNode name) {
    final JsonNode period = name.path("period");
    return (period.isObject() || period.isMissingNode() || period.isNull())
        && currentBoundary(period.path("start"), true)
        && currentBoundary(period.path("end"), false);
  }

  private boolean currentBoundary(final JsonNode boundary, final boolean startBoundary) {
    final Instant parsed = boundary.isTextual() ? parseInstant(boundary.textValue()) : null;
    return boundary.isMissingNode()
        || boundary.isNull()
        || parsed != null
            && (startBoundary
                ? !parsed.isAfter(clock.instant())
                : !parsed.isBefore(clock.instant()));
  }

  private static int nameRank(final JsonNode name) {
    return Map.of("official", 0, "usual", 1)
        .getOrDefault(Objects.toString(text(name, "use"), ""), 2);
  }

  private static String resourceId(final JsonNode node, final String type) {
    if (node == null || !node.isObject() || !type.equals(text(node, "resourceType"))) {
      throw invalid("resourceType");
    }
    validateTree(node, 0, new int[] {0});
    if (node.hasNonNull("implicitRules")) {
      throw invalid("implicitRules");
    }
    final String logicalId = text(node, "id");
    requireId(logicalId, "id");
    return logicalId;
  }

  private static void requireId(final String logicalId, final String field) {
    if (logicalId == null
        || DOT_SEGMENTS.contains(logicalId)
        || !logicalId.matches("[A-Za-z0-9\\-.]{1,64}")) {
      throw invalid(field);
    }
  }

  private static String text(final JsonNode node, final String field) {
    if (!node.isObject() && !node.isMissingNode() && !node.isNull()) {
      throw invalid(field);
    }
    final JsonNode value = node.get(field);
    if (value != null && !value.isNull() && !value.isTextual()) {
      throw invalid(field);
    }
    return value == null || value.isNull() ? null : value.textValue();
  }

  private static Iterable<JsonNode> array(final JsonNode node, final String field) {
    if (!node.isObject() && !node.isMissingNode() && !node.isNull()) {
      throw invalid(field);
    }
    final JsonNode value = node.get(field);
    if (value != null && !value.isNull() && !value.isArray()) {
      throw invalid(field);
    }
    return value == null || value.isNull() ? List.of() : value;
  }

  private static Instant instant(final JsonNode node, final String field) {
    final String raw = text(node, field);
    final Instant parsed = raw == null ? null : parseInstant(raw);
    if (raw != null && parsed == null) {
      throw invalid(field);
    }
    return parsed;
  }

  private static Instant parseInstant(final String raw) {
    final TemporalAccessor parsed =
        raw.matches(
                "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
                    + "(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})")
            ? parseTemporal(raw, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
            : null;
    return parsed == null ? null : OffsetDateTime.from(parsed).toInstant();
  }

  private static TemporalAccessor parseTemporal(
      final String raw, final DateTimeFormatter formatter) {
    final ParsePosition position = new ParsePosition(0);
    final Object parsed = formatter.toFormat().parseObject(raw, position);
    return position.getErrorIndex() >= 0 || position.getIndex() != raw.length()
        ? null
        : (TemporalAccessor) parsed;
  }

  private static void copy(
      final JsonNode resource, final ObjectNode projectionNode, final String... fields) {
    projectionNode.putObject("source");
    for (final String field : fields) {
      if (resource.has(field)) {
        ((ObjectNode) projectionNode.get("source")).set(field, resource.get(field).deepCopy());
      }
    }
  }

  private static void put(final ObjectNode projectionNode, final String field, final String value) {
    if (value != null) {
      projectionNode.put(field, value);
    }
  }

  private static void requireLink(final PatientLink link) {
    if (link == null) {
      throw invalid("link");
    }
  }

  // Bound traversal before copying. HTTP callers must also bound bytes before JSON parsing.
  private static void validateTree(final JsonNode node, final int depth, final int... count) {
    count[0]++;
    if (depth > 32 || count[0] > 10_000) {
      throw invalid("resourceSize");
    }
    if (node.isTextual() && node.textValue().length() > 100_000) {
      throw invalid("fieldSize");
    }
    if (node.isObject()) {
      final JsonNode modifiers = node.get("modifierExtension");
      if (modifiers != null
          && !modifiers.isNull()
          && (!modifiers.isArray() || !modifiers.isEmpty())) {
        throw invalid("modifierExtension");
      }
    }
    for (final JsonNode child : node) {
      validateTree(child, depth + 1, count);
    }
  }

  private static IllegalArgumentException invalid(final String field) {
    // Never include source values or parser causes resource errors.
    return new IllegalArgumentException("Invalid Cerner field: " + field);
  }
}
