package com.careconnect.testsupport.fixtures;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

/**
 * Shared athenahealth FHIR payloads for backend unit tests.
 *
 * <p>
 * Builders produce the shapes the preview sandbox actually returns, including its quirks: search
 * results marked {@code search.mode}, outcome entries mixed into a 200 bundle, cursor paging in
 * {@code link[next]}, and a 403 body whose {@code details} is a bare string. Captured sandbox
 * responses under {@code src/test/resources/athena} are available through {@link #captured}.
 * </p>
 */
public final class AthenaFhirFixtures {

    public static final ObjectMapper JSON = new ObjectMapper();

    /** Romilda Smith's sandbox chart, the seeded happy-path patient. */
    public static final String ROMILDA_ID = "a-195900.E-10037";

    private AthenaFhirFixtures() {
        // Utility class
    }

    /** A captured sandbox response, e.g. {@code "Patient-single.json"}. */
    public static String captured(final String name) {
        try (InputStream in = AthenaFhirFixtures.class.getResourceAsStream("/athena/" + name)) {
            if (in == null) {
                throw new IllegalArgumentException("no captured athena fixture " + name);
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException ex) {
            throw new UncheckedIOException(ex);
        }
    }

    /** A Patient with one name, as athena returns it. Pass null to omit a field. */
    public static ObjectNode patient(final String id, final String family, final String given,
                                     final String birthDate, final String gender) {
        final ObjectNode patient = JSON.createObjectNode().put("resourceType", "Patient").put("id", id);
        final ObjectNode name = patient.putArray("name").addObject();
        name.put("family", family);
        name.putArray("given").add(given);
        if (birthDate != null) {
            patient.put("birthDate", birthDate);
        }
        if (gender != null) {
            patient.put("gender", gender);
        }
        return patient;
    }

    /** Romilda's chart as the sandbox holds it. */
    public static ObjectNode romilda() {
        return patient(ROMILDA_ID, "Smith", "Romilda", "1976-02-28", "female");
    }

    /** A Condition whose clinicalStatus is {@code clinicalStatus}, e.g. "active" or "resolved". */
    public static ObjectNode condition(final String id, final String clinicalStatus,
                                       final String codeText, final String onset) {
        final ObjectNode condition = JSON.createObjectNode().put("resourceType", "Condition").put("id", id);
        condition.putObject("clinicalStatus").putArray("coding").addObject().put("code", clinicalStatus);
        condition.putObject("code").put("text", codeText);
        if (onset != null) {
            condition.put("onsetDateTime", onset);
        }
        return condition;
    }

    /** A searchset Bundle with each resource as a {@code match} entry and no next page. */
    public static String bundle(final JsonNode... resources) {
        return bundleWithNext(null, resources);
    }

    /** A searchset Bundle whose {@code link[next]} is {@code nextUrl}; null means the last page. */
    public static String bundleWithNext(final String nextUrl, final JsonNode... entries) {
        final ObjectNode bundle = JSON.createObjectNode().put("resourceType", "Bundle").put("type", "searchset");
        if (nextUrl != null) {
            bundle.putArray("link").addObject().put("relation", "next").put("url", nextUrl);
        }
        final ArrayNode array = bundle.putArray("entry");
        for (final JsonNode entry : entries) {
            if (entry.has("search")) {
                array.add(entry);
            } else {
                final ObjectNode wrapped = array.addObject();
                wrapped.set("resource", entry);
                wrapped.putObject("search").put("mode", "match");
            }
        }
        return bundle.toString();
    }

    /**
     * A Bundle entry carrying an OperationOutcome, the way athena reports an over-broad query inside
     * an HTTP 200 instead of failing the request.
     */
    public static ObjectNode outcomeEntry(final String severity, final String code) {
        final ObjectNode entry = JSON.createObjectNode();
        final ObjectNode outcome = entry.putObject("resource").put("resourceType", "OperationOutcome");
        outcome.putArray("issue").addObject().put("severity", severity).put("code", code);
        entry.putObject("search").put("mode", "outcome");
        return entry;
    }
}
