package com.careconnect.medicare;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;

/**
 * Response wrapper for every Medicare read.
 *
 * <p>The envelope is the stable part of the contract and the {@code resources} elements are the
 * part still in flux: they carry raw FHIR R4 today and will carry mapped views once
 * {@code BlueButton_FHIR_to_UI_Mapping.docx} is confirmed (see {@link MedicareResponseMapper}).
 * A client that binds to the envelope keeps working across that change.
 *
 * <p>{@code synthetic} is not decoration. A caller rendering claims or clinical history has to
 * be able to tell fabricated data from a real beneficiary's record without inspecting config,
 * so the answer travels with the payload.
 *
 * @param source     source discriminator, always {@code MEDICARE}
 * @param mode       {@code mock} or {@code live}
 * @param synthetic  true when the payload is fixture data and not a real beneficiary's record
 * @param total      number of resources returned, after the status gate
 * @param resources  the resources themselves
 */
public record MedicareEnvelope(
        String source,
        String mode,
        boolean synthetic,
        int total,
        List<JsonNode> resources) {

    /** Envelope for a list-valued read. */
    public static MedicareEnvelope of(final String mode, final boolean synthetic, final List<JsonNode> resources) {
        final List<JsonNode> safe = resources == null ? List.of() : resources;
        return new MedicareEnvelope(
                MedicareProperties.SOURCE_MEDICARE, mode, synthetic, safe.size(), safe);
    }

    /**
     * Envelope for a single-valued read.
     *
     * <p>Still a list, so that a caller parses one shape rather than two. A missing resource is
     * an empty list with {@code total} 0, not a null element.
     */
    public static MedicareEnvelope ofSingle(final String mode, final boolean synthetic, final JsonNode resource) {
        return of(mode, synthetic, resource == null || resource.isNull() ? List.of() : List.of(resource));
    }
}
