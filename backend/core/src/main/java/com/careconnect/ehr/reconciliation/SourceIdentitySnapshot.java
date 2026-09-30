package com.careconnect.ehr.reconciliation;

import java.time.Instant;
import java.util.Map;

/**
 * One adapter's demographic snapshot for one patient, as it would be upserted into
 * {@code ehr_source_identity}. This is the only input the reconciliation pattern needs — every
 * adapter (athenahealth, Epic, Oracle Health, Medicare's eventual sibling) builds one of these from
 * its own FHIR {@code Patient} resource and calls {@link IdentityReconciler#reconcile} with it. No
 * adapter computes a winner itself; that's this library's job.
 *
 * @param patientId       the internal CareConnect {@code patient.id} this snapshot is for.
 * @param sourceId        the {@code ehr_source.id} this snapshot came from.

 * @param sourceUpdatedAt this snapshot's provenance timestamp — FHIR {@code meta.lastUpdated} for the
 *                        resource the fields below were mapped from. This is the one timestamp the
 *                        entire recency-wins decision hangs on; if an adapter can't populate it
 *                        faithfully from the source system, do not fall back to "now" — that silently
 *                        turns every sync into a guaranteed win regardless of actual freshness.
 * @param fields          field name (matching {@code ehr_identity_conflict.field_name} convention,
 *                        e.g. {@code "first_name"}, {@code "address_line1"}, {@code "date_of_birth"})
 *                        to the mapped value as a string. A field this adapter has no value for should
 *                        be omitted from the map entirely, not included as {@code null} or {@code ""}
 *                        — this library never treats a blank incoming value as authoritative (see
 *                        {@link RecencyWinsIdentityReconciler}).
 */
public record SourceIdentitySnapshot(
        Long patientId,
        Long sourceId,
        Instant sourceUpdatedAt,
        Map<String, String> fields) {
}
