package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrMedicationRecord;
import com.careconnect.model.ehr.EhrObservationRecord;
import com.careconnect.repository.ehr.EhrConditionRecordRepository;
import com.careconnect.repository.ehr.EhrMedicationRecordRepository;
import com.careconnect.repository.ehr.EhrObservationRecordRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.time.Instant;
import java.time.LocalDate;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link EpicCanonicalProjector} — the JSON -> typed-table projection (Cononical_5_1
 * Step 6). Pure Mockito: the three record repositories are mocked and the saved entity is captured.
 * These cover the mapping logic that the {@code EpicSyncService*} suites only ever mock away.
 */
class EpicCanonicalProjectorTest {

    private final EhrMedicationRecordRepository medRepo = mock(EhrMedicationRecordRepository.class);
    private final EhrConditionRecordRepository condRepo = mock(EhrConditionRecordRepository.class);
    private final EhrObservationRecordRepository obsRepo = mock(EhrObservationRecordRepository.class);
    private final ObjectMapper mapper = new ObjectMapper();
    private final EpicCanonicalProjector projector =
            new EpicCanonicalProjector(medRepo, condRepo, obsRepo);

    private JsonNode json(final String raw) {
        try {
            return mapper.readTree(raw);
        } catch (final Exception e) {
            throw new RuntimeException(e);
        }
    }

    // --- guards / no-ops -------------------------------------------------

    @Test
    void project_isNoOp_whenAnyIdOrResourceIsNull() {
        final JsonNode med = json("{\"resourceType\":\"MedicationRequest\",\"id\":\"m1\"}");
        projector.project(null, 3L, "MedicationRequest", med);
        projector.project(7L, null, "MedicationRequest", med);
        projector.project(7L, 3L, null, med);
        projector.project(7L, 3L, "MedicationRequest", null);
        verifyNoInteractions(medRepo, condRepo, obsRepo);
    }

    @Test
    void project_isNoOp_whenResourceHasNoId() {
        projector.project(7L, 3L, "Condition", json("{\"resourceType\":\"Condition\"}"));
        projector.project(7L, 3L, "Condition", json("{\"resourceType\":\"Condition\",\"id\":\"\"}"));
        verifyNoInteractions(medRepo, condRepo, obsRepo);
    }

    @Test
    void project_isNoOp_forAnUnprojectedType() {
        projector.project(7L, 3L, "AllergyIntolerance",
                json("{\"resourceType\":\"AllergyIntolerance\",\"id\":\"a1\"}"));
        verifyNoInteractions(medRepo, condRepo, obsRepo);
    }

    // --- medication ------------------------------------------------------

    @Test
    void project_medicationRequest_mapsAllFields() {
        final JsonNode med = json("{"
                + "\"resourceType\":\"MedicationRequest\",\"id\":\"med-1\","
                + "\"meta\":{\"lastUpdated\":\"2026-09-01T10:00:00Z\"},"
                + "\"status\":\"active\",\"authoredOn\":\"2026-08-15\","
                + "\"medicationCodeableConcept\":{\"text\":\"Lisinopril 10mg\",\"coding\":[{"
                + "  \"system\":\"http://www.nlm.nih.gov/research/umls/rxnorm\",\"code\":\"314076\","
                + "  \"display\":\"Lisinopril\"}]},"
                + "\"dosageInstruction\":[{\"text\":\"Take one tablet daily\","
                + "  \"route\":{\"text\":\"oral\"},\"timing\":{\"code\":{\"text\":\"daily\"}}}]}");

        projector.project(7L, 3L, "MedicationRequest", med);

        final ArgumentCaptor<EhrMedicationRecord> saved = ArgumentCaptor.forClass(EhrMedicationRecord.class);
        verify(medRepo).save(saved.capture());
        final EhrMedicationRecord row = saved.getValue();
        assertThat(row.getPatientId()).isEqualTo(7L);
        assertThat(row.getSourceId()).isEqualTo(3L);
        assertThat(row.getExternalMedicationId()).isEqualTo("med-1");
        assertThat(row.getSourceUpdatedAt()).isEqualTo(Instant.parse("2026-09-01T10:00:00Z"));
        assertThat(row.getMedicationDisplay()).isEqualTo("Lisinopril 10mg");
        assertThat(row.getRxnormCode()).isEqualTo("314076");
        assertThat(row.getDosageText()).isEqualTo("Take one tablet daily");
        assertThat(row.getRoute()).isEqualTo("oral");
        assertThat(row.getFrequency()).isEqualTo("daily");
        assertThat(row.getAuthoredOn()).isEqualTo(LocalDate.of(2026, 8, 15));
        assertThat(row.getStatus()).isEqualTo("active");
    }

    @Test
    void project_medicationStatement_usesDosageArrayAndDateAssertedAndCodingDisplay() {
        final JsonNode med = json("{"
                + "\"resourceType\":\"MedicationStatement\",\"id\":\"ms-1\","
                + "\"meta\":{\"lastUpdated\":\"2026-07-10T00:00:00Z\"},"
                + "\"status\":\"active\",\"dateAsserted\":\"2026-07-01\","
                + "\"medicationCodeableConcept\":{\"coding\":[{\"system\":\"rxnorm\",\"code\":\"111\","
                + "  \"display\":\"DrugX\"}]},"
                + "\"dosage\":[{\"text\":\"5ml BID\",\"route\":{\"coding\":[{\"display\":\"IV\"}]},"
                + "  \"timing\":{\"code\":{\"text\":\"BID\"}}}]}");

        projector.project(7L, 3L, "MedicationStatement", med);

        final ArgumentCaptor<EhrMedicationRecord> saved = ArgumentCaptor.forClass(EhrMedicationRecord.class);
        verify(medRepo).save(saved.capture());
        final EhrMedicationRecord row = saved.getValue();
        assertThat(row.getMedicationDisplay()).isEqualTo("DrugX"); // coding display, no text
        assertThat(row.getRxnormCode()).isEqualTo("111");
        assertThat(row.getDosageText()).isEqualTo("5ml BID");
        assertThat(row.getRoute()).isEqualTo("IV");
        assertThat(row.getFrequency()).isEqualTo("BID");
        assertThat(row.getAuthoredOn()).isEqualTo(LocalDate.of(2026, 7, 1)); // dateAsserted fallback
    }

    @Test
    void project_medication_fallsBackToMedicationReferenceDisplay() {
        final JsonNode med = json("{"
                + "\"resourceType\":\"Medication\",\"id\":\"m-ref\","
                + "\"meta\":{\"lastUpdated\":\"2026-01-01T00:00:00Z\"},"
                + "\"medicationReference\":{\"display\":\"Referenced Drug\"}}");

        projector.project(7L, 3L, "Medication", med);

        final ArgumentCaptor<EhrMedicationRecord> saved = ArgumentCaptor.forClass(EhrMedicationRecord.class);
        verify(medRepo).save(saved.capture());
        assertThat(saved.getValue().getMedicationDisplay()).isEqualTo("Referenced Drug");
        assertThat(saved.getValue().getRxnormCode()).isNull();
    }

    @Test
    void project_medication_yearOnlyAuthoredOn_leavesDateNull() {
        final JsonNode med = json("{"
                + "\"resourceType\":\"MedicationRequest\",\"id\":\"m-y\","
                + "\"meta\":{\"lastUpdated\":\"2026-01-01T00:00:00Z\"},\"authoredOn\":\"2026\"}");

        projector.project(7L, 3L, "MedicationRequest", med);

        final ArgumentCaptor<EhrMedicationRecord> saved = ArgumentCaptor.forClass(EhrMedicationRecord.class);
        verify(medRepo).save(saved.capture());
        assertThat(saved.getValue().getAuthoredOn()).isNull();
    }

    @Test
    void project_medication_noMetaLastUpdated_fallsBackToNow() {
        final Instant before = Instant.now();
        projector.project(7L, 3L, "MedicationRequest",
                json("{\"resourceType\":\"MedicationRequest\",\"id\":\"m-now\"}"));

        final ArgumentCaptor<EhrMedicationRecord> saved = ArgumentCaptor.forClass(EhrMedicationRecord.class);
        verify(medRepo).save(saved.capture());
        assertThat(saved.getValue().getSourceUpdatedAt())
                .isNotNull()
                .isCloseTo(before, within(1, java.time.temporal.ChronoUnit.MINUTES));
    }

    @Test
    void project_medication_reusesExistingRowOnResync() {
        final EhrMedicationRecord existing = new EhrMedicationRecord();
        existing.setId(99L);
        when(medRepo.findByPatientIdAndSourceIdAndExternalMedicationId(7L, 3L, "med-1"))
                .thenReturn(Optional.of(existing));

        projector.project(7L, 3L, "MedicationRequest", json("{"
                + "\"resourceType\":\"MedicationRequest\",\"id\":\"med-1\","
                + "\"meta\":{\"lastUpdated\":\"2026-09-01T10:00:00Z\"},\"status\":\"active\"}"));

        final ArgumentCaptor<EhrMedicationRecord> saved = ArgumentCaptor.forClass(EhrMedicationRecord.class);
        verify(medRepo).save(saved.capture());
        assertThat(saved.getValue().getId()).isEqualTo(99L); // upsert, not a duplicate insert
        assertThat(saved.getValue().getStatus()).isEqualTo("active");
    }

    // --- condition -------------------------------------------------------

    @Test
    void project_condition_mapsAllFields() {
        final JsonNode cond = json("{"
                + "\"resourceType\":\"Condition\",\"id\":\"cond-1\","
                + "\"meta\":{\"lastUpdated\":\"2026-02-01T00:00:00Z\"},"
                + "\"code\":{\"text\":\"Hypertension\",\"coding\":[{\"system\":\"icd10\",\"code\":\"I10\","
                + "  \"display\":\"Essential hypertension\"}]},"
                + "\"clinicalStatus\":{\"coding\":[{\"code\":\"active\"}]},"
                + "\"verificationStatus\":{\"coding\":[{\"code\":\"confirmed\"}]},"
                + "\"onsetDateTime\":\"2020-01-05\",\"recordedDate\":\"2021-02-10\"}");

        projector.project(7L, 3L, "Condition", cond);

        final ArgumentCaptor<EhrConditionRecord> saved = ArgumentCaptor.forClass(EhrConditionRecord.class);
        verify(condRepo).save(saved.capture());
        final EhrConditionRecord row = saved.getValue();
        assertThat(row.getExternalConditionId()).isEqualTo("cond-1");
        assertThat(row.getConditionDisplay()).isEqualTo("Hypertension");
        assertThat(row.getCode()).isEqualTo("I10");
        assertThat(row.getClinicalStatus()).isEqualTo("active");
        assertThat(row.getVerificationStatus()).isEqualTo("confirmed");
        assertThat(row.getOnsetDate()).isEqualTo(LocalDate.of(2020, 1, 5));
        assertThat(row.getRecordedDate()).isEqualTo("2021-02-10");
        assertThat(row.getRecordedDatePrecision()).isEqualTo("DAY");
    }

    // --- observation -----------------------------------------------------

    @Test
    void project_observation_quantityAndLowHighReferenceRange() {
        final JsonNode obs = json("{"
                + "\"resourceType\":\"Observation\",\"id\":\"obs-1\","
                + "\"meta\":{\"lastUpdated\":\"2026-05-01T00:00:00Z\"},\"status\":\"final\","
                + "\"code\":{\"text\":\"Systolic BP\",\"coding\":[{\"system\":\"http://loinc.org\","
                + "  \"code\":\"8480-6\",\"display\":\"Systolic\"}]},"
                + "\"category\":[{\"coding\":[{\"code\":\"vital-signs\"}]}],"
                + "\"valueQuantity\":{\"value\":120,\"unit\":\"mmHg\"},"
                + "\"referenceRange\":[{\"low\":{\"value\":90,\"unit\":\"mmHg\"},"
                + "  \"high\":{\"value\":140,\"unit\":\"mmHg\"}}],"
                + "\"effectiveDateTime\":\"2026-05-01\"}");

        projector.project(7L, 3L, "Observation", obs);

        final ArgumentCaptor<EhrObservationRecord> saved = ArgumentCaptor.forClass(EhrObservationRecord.class);
        verify(obsRepo).save(saved.capture());
        final EhrObservationRecord row = saved.getValue();
        assertThat(row.getExternalObservationId()).isEqualTo("obs-1");
        assertThat(row.getObservationDisplay()).isEqualTo("Systolic BP");
        assertThat(row.getLoincCode()).isEqualTo("8480-6");
        assertThat(row.getCategory()).isEqualTo("vital-signs");
        assertThat(row.getValueQuantity()).isEqualTo(120.0);
        assertThat(row.getValueUnit()).isEqualTo("mmHg");
        assertThat(row.getReferenceRange()).isEqualTo("90 mmHg - 140 mmHg");
        assertThat(row.getEffectiveDate()).isEqualTo(LocalDate.of(2026, 5, 1));
        assertThat(row.getStatus()).isEqualTo("final");
    }

    @Test
    void project_observation_valueStringTextRangeAndEffectivePeriod() {
        final JsonNode obs = json("{"
                + "\"resourceType\":\"Observation\",\"id\":\"obs-2\","
                + "\"meta\":{\"lastUpdated\":\"2026-06-01T00:00:00Z\"},"
                + "\"code\":{\"coding\":[{\"system\":\"loinc\",\"code\":\"X\",\"display\":\"Note\"}]},"
                + "\"valueString\":\"Positive\","
                + "\"referenceRange\":[{\"text\":\"Negative\"}],"
                + "\"effectivePeriod\":{\"start\":\"2026-06-01T08:00:00Z\"}}");

        projector.project(7L, 3L, "Observation", obs);

        final ArgumentCaptor<EhrObservationRecord> saved = ArgumentCaptor.forClass(EhrObservationRecord.class);
        verify(obsRepo).save(saved.capture());
        final EhrObservationRecord row = saved.getValue();
        assertThat(row.getValueString()).isEqualTo("Positive");
        assertThat(row.getValueQuantity()).isNull();
        assertThat(row.getReferenceRange()).isEqualTo("Negative");
        assertThat(row.getEffectiveDate()).isEqualTo(LocalDate.of(2026, 6, 1));
    }

    @Test
    void project_observation_clearsStaleQuantityWhenResyncedAsTextOnly() {
        // Existing row carries a numeric value/unit from a prior numeric sync.
        final EhrObservationRecord existing = new EhrObservationRecord();
        existing.setId(42L);
        existing.setValueQuantity(9.1);
        existing.setValueUnit("mg/dL");
        when(obsRepo.findByPatientIdAndSourceIdAndExternalObservationId(7L, 3L, "obs-rs"))
                .thenReturn(Optional.of(existing));

        // Source re-issues the same observation as text-only: no valueQuantity.
        projector.project(7L, 3L, "Observation", json("{"
                + "\"resourceType\":\"Observation\",\"id\":\"obs-rs\","
                + "\"meta\":{\"lastUpdated\":\"2026-07-01T00:00:00Z\"},"
                + "\"code\":{\"coding\":[{\"system\":\"loinc\",\"code\":\"X\",\"display\":\"Note\"}]},"
                + "\"valueString\":\"see comment\"}"));

        final ArgumentCaptor<EhrObservationRecord> saved = ArgumentCaptor.forClass(EhrObservationRecord.class);
        verify(obsRepo).save(saved.capture());
        final EhrObservationRecord row = saved.getValue();
        assertThat(row.getId()).isEqualTo(42L);            // upsert, same row
        assertThat(row.getValueString()).isEqualTo("see comment");
        assertThat(row.getValueQuantity()).isNull();       // stale numeric cleared
        assertThat(row.getValueUnit()).isNull();           // stale unit cleared
    }

    // --- disconnect cleanup ---------------------------------------------

    @Test
    void deleteAllForPatientAndSource_sumsThreeRepos() {
        when(medRepo.deleteAllForPatientAndSource(7L, 3L)).thenReturn(2);
        when(condRepo.deleteAllForPatientAndSource(7L, 3L)).thenReturn(3);
        when(obsRepo.deleteAllForPatientAndSource(7L, 3L)).thenReturn(5);

        assertThat(projector.deleteAllForPatientAndSource(7L, 3L)).isEqualTo(10);
    }

    @Test
    void deleteAllForPatientAndSource_nullIds_returnsZeroWithNoRepoCalls() {
        assertThat(projector.deleteAllForPatientAndSource(null, 3L)).isZero();
        assertThat(projector.deleteAllForPatientAndSource(7L, null)).isZero();
        verify(medRepo, never()).deleteAllForPatientAndSource(any(), any());
        verify(condRepo, never()).deleteAllForPatientAndSource(any(), any());
        verify(obsRepo, never()).deleteAllForPatientAndSource(any(), any());
    }
}
