package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrMedicationRecord;
import com.careconnect.model.ehr.EhrObservationRecord;
import com.careconnect.repository.ehr.EhrConditionRecordRepository;
import com.careconnect.repository.ehr.EhrMedicationRecordRepository;
import com.careconnect.repository.ehr.EhrObservationRecordRepository;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Locale;

/**
 * Projects a status-gated Epic FHIR resource into its typed canonical table — Cononical_5_1 Step 6,
 * Team E brief S5 ("Project into typed tables"). Three tables are built here:
 * {@link EhrMedicationRecord} (MedicationRequest / MedicationStatement / Medication),
 * {@link EhrConditionRecord} (Condition) and {@link EhrObservationRecord} (Observation).
 *
 * <p>Unlike the Medicare connector, which maps HAPI FHIR objects, the Epic connector works in
 * {@code JsonNode}, so projection reads JSON directly. Each resource is upserted by
 * {@code (patient_id, source_id, external_*_id)} — the unique key — so a re-sync refreshes rather
 * than duplicates. Called from {@code EpicSyncService.upsertAndEmit}, inside the same per-resource
 * transaction, after the raw-payload write; the caller has already applied {@code EhrStatusGate}
 * and guaranteed a non-blank resource id, and skips the canonical writes when the ids are unresolved.
 *
 * <p>Resource types this does not project are a no-op (the raw payload and the {@code ehr_resource}
 * mirror still hold them).
 */
@Slf4j
@Component
public class EpicCanonicalProjector {

    private final EhrMedicationRecordRepository medicationRepo;
    private final EhrConditionRecordRepository conditionRepo;
    private final EhrObservationRecordRepository observationRepo;

    public EpicCanonicalProjector(
            final EhrMedicationRecordRepository medicationRepo,
            final EhrConditionRecordRepository conditionRepo,
            final EhrObservationRecordRepository observationRepo) {
        this.medicationRepo = medicationRepo;
        this.conditionRepo = conditionRepo;
        this.observationRepo = observationRepo;
    }

    /**
     * Project one resource into its typed table if the type is one we project. No-op for other
     * types, for a null/unresolved patient or source id, or for a resource with no id.
     */
    public void project(final Long patientId, final Long sourceId,
                        final String resourceType, final JsonNode resource) {
        if (patientId == null || sourceId == null || resourceType == null || resource == null) {
            return;
        }
        final String externalId = text(resource, "id");
        if (externalId == null || externalId.isBlank()) {
            return;
        }
        final Instant sourceUpdatedAt = metaLastUpdated(resource);
        switch (resourceType) {
            case "MedicationRequest":
            case "MedicationStatement":
            case "Medication":
                projectMedication(patientId, sourceId, externalId, sourceUpdatedAt, resource);
                break;
            case "Condition":
                projectCondition(patientId, sourceId, externalId, sourceUpdatedAt, resource);
                break;
            case "Observation":
                projectObservation(patientId, sourceId, externalId, sourceUpdatedAt, resource);
                break;
            default:
                // Not a projected type; the raw payload and ehr_resource mirror still hold it.
        }
    }

    /**
     * Remove every typed projection row this source holds for the patient (disconnect / purge
     * cleanup, Cononical_5_1 "canonical write discipline"). Returns the total rows removed.
     */
    public int deleteAllForPatientAndSource(final Long patientId, final Long sourceId) {
        if (patientId == null || sourceId == null) {
            return 0;
        }
        return medicationRepo.deleteAllForPatientAndSource(patientId, sourceId)
                + conditionRepo.deleteAllForPatientAndSource(patientId, sourceId)
                + observationRepo.deleteAllForPatientAndSource(patientId, sourceId);
    }

    private void projectMedication(final Long patientId, final Long sourceId, final String externalId,
                                   final Instant sourceUpdatedAt, final JsonNode r) {
        final EhrMedicationRecord row = medicationRepo
                .findByPatientIdAndSourceIdAndExternalMedicationId(patientId, sourceId, externalId)
                .orElseGet(EhrMedicationRecord::new);
        row.setPatientId(patientId);
        row.setSourceId(sourceId);
        row.setExternalMedicationId(externalId);
        row.setSourceUpdatedAt(sourceUpdatedAt);

        final JsonNode medConcept = r.get("medicationCodeableConcept");
        row.setMedicationDisplay(medConcept != null
                ? conceptDisplay(medConcept)
                : text(r.get("medicationReference"), "display"));
        row.setRxnormCode(codingCodeBySystem(medConcept, "rxnorm"));

        final JsonNode dosage = firstOf(r, "dosageInstruction");
        final JsonNode dosageStmt = firstOf(r, "dosage"); // MedicationStatement
        final JsonNode dose = dosage != null ? dosage : dosageStmt;
        if (dose != null) {
            row.setDosageText(text(dose, "text"));
            row.setRoute(conceptDisplay(dose.get("route")));
            row.setFrequency(conceptDisplay(timingCode(dose)));
        }
        row.setAuthoredOn(toLocalDate(firstNonBlank(
                text(r, "authoredOn"), text(r, "dateAsserted"), text(r, "effectiveDateTime"))));
        row.setStatus(text(r, "status"));
        medicationRepo.save(row);
    }

    private void projectCondition(final Long patientId, final Long sourceId, final String externalId,
                                  final Instant sourceUpdatedAt, final JsonNode r) {
        final EhrConditionRecord row = conditionRepo
                .findByPatientIdAndSourceIdAndExternalConditionId(patientId, sourceId, externalId)
                .orElseGet(EhrConditionRecord::new);
        row.setPatientId(patientId);
        row.setSourceId(sourceId);
        row.setExternalConditionId(externalId);
        row.setSourceUpdatedAt(sourceUpdatedAt);

        final JsonNode code = r.get("code");
        row.setConditionDisplay(conceptDisplay(code));
        row.setCode(firstCode(code));
        row.setClinicalStatus(firstCode(r.get("clinicalStatus")));
        row.setVerificationStatus(firstCode(r.get("verificationStatus")));
        row.setOnsetDate(toLocalDate(text(r, "onsetDateTime")));
        row.setRecordedDate(toLocalDate(text(r, "recordedDate")));
        conditionRepo.save(row);
    }

    private void projectObservation(final Long patientId, final Long sourceId, final String externalId,
                                    final Instant sourceUpdatedAt, final JsonNode r) {
        final EhrObservationRecord row = observationRepo
                .findByPatientIdAndSourceIdAndExternalObservationId(patientId, sourceId, externalId)
                .orElseGet(EhrObservationRecord::new);
        row.setPatientId(patientId);
        row.setSourceId(sourceId);
        row.setExternalObservationId(externalId);
        row.setSourceUpdatedAt(sourceUpdatedAt);

        final JsonNode code = r.get("code");
        row.setObservationDisplay(conceptDisplay(code));
        row.setLoincCode(codingCodeBySystem(code, "loinc"));
        row.setCategory(firstCode(firstOf(r, "category")));

        final JsonNode valueQuantity = r.get("valueQuantity");
        if (valueQuantity != null && valueQuantity.hasNonNull("value")) {
            row.setValueQuantity(valueQuantity.get("value").asDouble());
            row.setValueUnit(text(valueQuantity, "unit"));
        }
        row.setValueString(text(r, "valueString"));
        row.setReferenceRange(referenceRange(firstOf(r, "referenceRange")));
        row.setEffectiveDate(toLocalDate(firstNonBlank(
                text(r, "effectiveDateTime"), text(r.get("effectivePeriod"), "start"))));
        row.setStatus(text(r, "status"));
        observationRepo.save(row);
    }

    // --- JSON helpers ---

    private static String text(final JsonNode node, final String field) {
        if (node == null) {
            return null;
        }
        final JsonNode v = node.get(field);
        return v != null && !v.isNull() ? v.asText() : null;
    }

    /** First element of an array field, or null. */
    private static JsonNode firstOf(final JsonNode node, final String arrayField) {
        if (node == null) {
            return null;
        }
        final JsonNode arr = node.get(arrayField);
        return arr != null && arr.isArray() && !arr.isEmpty() ? arr.get(0) : null;
    }

    /** A CodeableConcept's {@code text}, else its first coding's {@code display}. */
    private static String conceptDisplay(final JsonNode concept) {
        if (concept == null) {
            return null;
        }
        if (concept.hasNonNull("text")) {
            return concept.get("text").asText();
        }
        final JsonNode c0 = firstOf(concept, "coding");
        return c0 != null && c0.hasNonNull("display") ? c0.get("display").asText() : null;
    }

    /** The code from the first coding whose {@code system} contains {@code systemToken} (case-insensitive). */
    private static String codingCodeBySystem(final JsonNode concept, final String systemToken) {
        if (concept == null) {
            return null;
        }
        final JsonNode coding = concept.get("coding");
        if (coding != null && coding.isArray()) {
            for (final JsonNode c : coding) {
                final String sys = c.hasNonNull("system") ? c.get("system").asText() : "";
                if (sys.toLowerCase(Locale.ROOT).contains(systemToken) && c.hasNonNull("code")) {
                    return c.get("code").asText();
                }
            }
        }
        return null;
    }

    /** The first coding's {@code code}, regardless of system (e.g. ICD-10 or SNOMED on a Condition). */
    private static String firstCode(final JsonNode concept) {
        final JsonNode c0 = firstOf(concept, "coding");
        return c0 != null && c0.hasNonNull("code") ? c0.get("code").asText() : null;
    }

    /** A dosage's {@code timing.code} CodeableConcept, or null. */
    private static JsonNode timingCode(final JsonNode dosage) {
        final JsonNode timing = dosage == null ? null : dosage.get("timing");
        return timing == null ? null : timing.get("code");
    }

    /** A referenceRange element's {@code text}, else "low - high" from its quantities. */
    private static String referenceRange(final JsonNode range) {
        if (range == null) {
            return null;
        }
        if (range.hasNonNull("text")) {
            return range.get("text").asText();
        }
        final String low = quantity(range.get("low"));
        final String high = quantity(range.get("high"));
        if (low == null && high == null) {
            return null;
        }
        return (low == null ? "" : low) + " - " + (high == null ? "" : high);
    }

    private static String quantity(final JsonNode q) {
        if (q == null || !q.hasNonNull("value")) {
            return null;
        }
        final String unit = q.hasNonNull("unit") ? " " + q.get("unit").asText() : "";
        return q.get("value").asText() + unit;
    }

    /** Parse a FHIR date/dateTime to a calendar date; null unless it carries at least day precision. */
    private static LocalDate toLocalDate(final String value) {
        if (value == null || value.length() < 10) {
            return null;
        }
        final String d = value.substring(0, 10);
        if (!d.matches("\\d{4}-\\d{2}-\\d{2}")) {
            return null;
        }
        try {
            return LocalDate.parse(d);
        } catch (final RuntimeException ignored) {
            return null;
        }
    }

    private static String firstNonBlank(final String... values) {
        for (final String v : values) {
            if (v != null && !v.isBlank()) {
                return v;
            }
        }
        return null;
    }

    /** {@code meta.lastUpdated} as an Instant, or now when the source omits it (column is NOT NULL). */
    private static Instant metaLastUpdated(final JsonNode resource) {
        final JsonNode meta = resource.get("meta");
        if (meta != null && meta.hasNonNull("lastUpdated")) {
            try {
                return OffsetDateTime.parse(meta.get("lastUpdated").asText()).toInstant();
            } catch (final RuntimeException ignored) {
                // fall through to now()
            }
        }
        return Instant.now();
    }
}
