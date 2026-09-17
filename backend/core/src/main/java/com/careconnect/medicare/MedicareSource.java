package com.careconnect.medicare;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;

/**
 * Read-only port for Medicare (Blue Button 2.0) retrieval, WBS 1.4.1-1.4.2 / issue #132.
 *
 * <p>Deliberately Team Echo's own interface rather than a cross-team one. Two different
 * {@code EhrApiClient} interfaces exist today with incompatible signatures — Team Bravo's
 * {@code com.careconnect.client.ehr.EhrApiClient} and Team Delta's
 * {@code com.careconnect.service.ehr.EhrApiClient} — and neither has merged into
 * {@code team-e-develop}. Implementing either one here would make this branch depend on
 * another team's merge schedule. The method names below mirror the ones issue #132 specifies
 * ({@code fetchPatient} / {@code fetchCoverage} / {@code fetchVisits}), and {@code sourceCode()}
 * matches the spelling both peer interfaces already use, so adapting to whichever lands is a
 * single small class rather than a rewrite.
 *
 * <p>Returns raw FHIR R4 {@link JsonNode}s. Shaping into the UI contract belongs to
 * {@link MedicareResponseMapper}, not here, so that a mapping change never forces a retrieval
 * change.
 *
 * <p>Read-only by design: nothing in this package persists. Issue #132 has an open blocking
 * decision on whether {@code medicare_connection}/{@code medicare_records} (SRS 9.2) or the
 * WBS 1.4.3 canonical tables win, and ADR-08 forbids this source from writing the golden
 * {@code patient} record in any case.
 */
public interface MedicareSource {

    /** Discriminator for this source, matching the {@code ehr_source.code} convention. */
    String sourceCode();

    /**
     * The beneficiary's demographics.
     *
     * @return the {@code Patient} resource, or {@code null} when the source has none
     */
    JsonNode fetchPatient();

    /** The beneficiary's Medicare enrollment, one {@code Coverage} resource per part. */
    List<JsonNode> fetchCoverage();

    /**
     * The beneficiary's claims history as {@code ExplanationOfBenefit} resources.
     *
     * <p>Named "visits" rather than "claims" to match issue #132. An EOB is a billing record,
     * so it carries service dates, providers and amounts — not recurring clinical measurements.
     */
    List<JsonNode> fetchVisits();
}
