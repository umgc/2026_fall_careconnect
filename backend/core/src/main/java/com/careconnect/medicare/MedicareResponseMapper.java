package com.careconnect.medicare;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import org.springframework.stereotype.Component;

/**
 * Seam where raw Blue Button FHIR becomes the UI contract.
 *
 * <p><b>Passthrough today, on purpose.</b> The field contract is
 * {@code BlueButton_FHIR_to_UI_Mapping.docx} (issue #132, "parsing/mapping layer"), which is the
 * artifact the cohort is standardising on. Inventing field names here before that document is
 * confirmed would create a second contract for the frontend to reconcile against the first, so
 * these methods return the FHIR resource unchanged and the endpoints serve FHIR until the
 * mapping lands.
 *
 * <p>What this buys: the retrieval path, status gate, envelope, routes, security rules and
 * tests are all exercised now, and adopting the mapping is an edit to this one class rather
 * than a change that reaches the controller or the source.
 *
 * <p>Codes stay as {@code CodeableConcept} passthrough when the mapping is applied — issue #132
 * requires diagnosis and procedure codes to survive mapping rather than being flattened to a
 * display string.
 */
@Component
public class MedicareResponseMapper {

    /** @return the {@code Patient} resource as the UI should receive it. */
    public JsonNode toPatientView(final JsonNode patient) {
        return patient;
    }

    /** @return the {@code Coverage} resources as the UI should receive them. */
    public List<JsonNode> toCoverageView(final List<JsonNode> coverage) {
        return coverage == null ? List.of() : List.copyOf(coverage);
    }

    /** @return the {@code ExplanationOfBenefit} resources as the UI should receive them. */
    public List<JsonNode> toVisitView(final List<JsonNode> visits) {
        return visits == null ? List.of() : List.copyOf(visits);
    }
}
