package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrSourceIdentity;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;

/** Maps one FHIR Patient into the shared per-source demographic mirror. */
public final class EhrPatientIdentityMapper {

    private EhrPatientIdentityMapper() {
    }

    public static EhrSourceIdentity map(
            final JsonNode resource, final long patientId, final long sourceId) {
        if (resource == null || !"Patient".equals(resource.path("resourceType").asText())) {
            throw new IllegalArgumentException("FHIR Patient resource required");
        }
        final String updated = text(resource.path("meta"), "lastUpdated");
        if (updated == null) {
            throw new IllegalArgumentException(
                    "FHIR Patient meta.lastUpdated is required for safe reconciliation");
        }
        final EhrSourceIdentity.EhrSourceIdentityBuilder builder = EhrSourceIdentity.builder()
                .patientId(patientId)
                .sourceId(sourceId)
                .sourceUpdatedAt(parseInstant(updated))
                .givenName(givenName(resource))
                .familyName(text(first(resource, "name"), "family"))
                .dateOfBirth(fullDate(text(resource, "birthDate")))
                .phone(telecom(resource, "phone"))
                .email(telecom(resource, "email"))
                .gender(text(resource, "gender"))
                .memberId(text(first(resource, "identifier"), "value"))
                .managingOrg(text(resource.path("managingOrganization"), "display"))
                .language(language(resource));
        final JsonNode address = first(resource, "address");
        builder.addressLine1(arrayText(address.path("line"), 0))
                .addressLine2(arrayText(address.path("line"), 1))
                .city(text(address, "city"))
                .state(text(address, "state"))
                .postalCode(text(address, "postalCode"));
        return builder.build();
    }

    private static String givenName(final JsonNode resource) {
        return arrayText(first(resource, "name").path("given"), 0);
    }

    private static String telecom(final JsonNode resource, final String system) {
        for (final JsonNode point : resource.path("telecom")) {
            if (system.equals(text(point, "system"))) {
                return text(point, "value");
            }
        }
        return null;
    }

    private static String language(final JsonNode resource) {
        final JsonNode concept = first(resource, "communication").path("language");
        final String code = text(first(concept, "coding"), "code");
        return code != null ? code : text(concept, "text");
    }

    private static JsonNode first(final JsonNode resource, final String field) {
        if (resource == null) {
            return com.fasterxml.jackson.databind.node.MissingNode.getInstance();
        }
        final JsonNode values = resource.path(field);
        return values.isArray() && !values.isEmpty()
                ? values.get(0)
                : com.fasterxml.jackson.databind.node.MissingNode.getInstance();
    }

    private static String arrayText(final JsonNode values, final int index) {
        return values.isArray() && values.size() > index && !values.get(index).isNull()
                ? blankToNull(values.get(index).asText())
                : null;
    }

    private static String text(final JsonNode node, final String field) {
        if (node == null) {
            return null;
        }
        final JsonNode value = node.path(field);
        return value.isMissingNode() || value.isNull() ? null : blankToNull(value.asText());
    }

    private static String blankToNull(final String value) {
        return value == null || value.isBlank() ? null : value;
    }

    private static Instant parseInstant(final String value) {
        try {
            return Instant.parse(value);
        } catch (DateTimeParseException error) {
            throw new IllegalArgumentException("Invalid FHIR Patient meta.lastUpdated", error);
        }
    }

    private static LocalDate fullDate(final String value) {
        if (value == null || !value.matches("\\d{4}-\\d{2}-\\d{2}")) {
            return null;
        }
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException error) {
            return null;
        }
    }
}
