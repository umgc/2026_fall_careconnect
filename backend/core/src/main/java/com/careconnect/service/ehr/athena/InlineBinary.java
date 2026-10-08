package com.careconnect.service.ehr.athena;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * Removes inline binary content from a FHIR resource before it is stored anywhere.
 *
 * <p>Documents are out of scope for this integration, and the canonical schema requires inline
 * binary to be stripped before insert rather than trimmed afterwards. Besides
 * {@code Patient.photo}, a FHIR {@code Attachment} can carry a whole file base64-encoded in its
 * {@code data} element (a DiagnosticReport's {@code presentedForm} is typically a PDF), so every
 * Attachment's {@code data} goes too. The rest of the Attachment (type, title, url) is kept.
 */
final class InlineBinary {

    /** The resource as it may be stored, and whether anything was removed from it. */
    record Stripped(JsonNode body, boolean stripped) {
    }

    private InlineBinary() {
    }

    /** Returns a stripped copy; the input is never modified. */
    static Stripped strip(final JsonNode resource) {
        final JsonNode copy = resource.deepCopy();
        boolean stripped = false;
        if (copy instanceof ObjectNode object
                && "Patient".equals(object.path("resourceType").asText())
                && object.has("photo")) {
            object.remove("photo");
            stripped = true;
        }
        return new Stripped(copy, removeAttachmentData(copy) || stripped);
    }

    /**
     * An Attachment holding inline data must also state its contentType (FHIR invariant att-1),
     * which is what tells it apart from other elements named {@code data}, such as SampledData.
     */
    private static boolean removeAttachmentData(final JsonNode node) {
        boolean removed = false;
        if (node instanceof ObjectNode object) {
            if (object.path("data").isTextual() && object.has("contentType")) {
                object.remove("data");
                removed = true;
            }
            for (final JsonNode child : object) {
                removed |= removeAttachmentData(child);
            }
        } else if (node.isArray()) {
            for (final JsonNode child : node) {
                removed |= removeAttachmentData(child);
            }
        }
        return removed;
    }
}
