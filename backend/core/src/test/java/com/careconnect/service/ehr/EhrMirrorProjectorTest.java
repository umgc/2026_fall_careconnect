package com.careconnect.service.ehr;

import com.careconnect.config.OracleProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link EhrMirrorProjector} — the {@code ehr_raw_payload -> ehr_resource} mirror
 * projection (WBS 5.2.86 Phase B). Pure Mockito: repositories are mocked, a real {@link EhrStatusGate}
 * and {@link ObjectMapper} are used, and the saved {@link EhrResource} is captured to assert the
 * derived source / title / occurredAt / content-hash and the idempotent/skip branches.
 */
class EhrMirrorProjectorTest {

    private static final long USER = 7L;
    private static final long PATIENT = 3L;
    private static final long ORACLE_SRC_ID = 40L;
    private static final long MEDICARE_SRC_ID = 20L;

    private final EhrResourceRepository resourceRepo = mock(EhrResourceRepository.class);
    private final EhrRawPayloadRepository rawPayloadRepo = mock(EhrRawPayloadRepository.class);
    private final EhrSourceRepository sourceRepo = mock(EhrSourceRepository.class);
    private final PatientRepository patientRepository = mock(PatientRepository.class);
    private final EhrStatusGate statusGate = new EhrStatusGate();
    private final ObjectMapper mapper = new ObjectMapper();

    private final EhrMirrorProjector projector = new EhrMirrorProjector(
            resourceRepo, rawPayloadRepo, sourceRepo, patientRepository, statusGate, mapper);

    private EhrRawPayload raw(final String type, final String externalId, final String json) {
        return EhrRawPayload.builder()
                .patientId(PATIENT).sourceId(ORACLE_SRC_ID)
                .resourceType(type).externalResourceId(externalId).payload(json).build();
    }

    private EhrSource source(final long id, final String code) {
        final EhrSource s = new EhrSource();
        s.setId(id);
        s.setCode(code);
        return s;
    }

    private void stubOracleSource() {
        when(sourceRepo.findByCode(OracleProperties.SOURCE_ORACLE))
                .thenReturn(Optional.of(source(ORACLE_SRC_ID, OracleProperties.SOURCE_ORACLE)));
    }

    private void stubNoExisting() {
        when(resourceRepo.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
                anyLong(), any(), any(), any())).thenReturn(Optional.empty());
    }

    // --- projectForSource: guards -----------------------------------------

    @Test
    void nonMirrorableSourceIsNeverProjected() {
        assertThat(projector.projectForSource(USER, PATIENT, "EPIC")).isZero();
        verify(resourceRepo, never()).save(any());
    }

    @Test
    void unseededSourceReturnsZero() {
        when(sourceRepo.findByCode(OracleProperties.SOURCE_ORACLE)).thenReturn(Optional.empty());
        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isZero();
        verify(resourceRepo, never()).save(any());
    }

    // --- project: one row, happy path + field derivation ------------------

    @Test
    void mirrorsAConditionWithDerivedTitleOccurredAtAndHash() {
        stubOracleSource();
        stubNoExisting();
        final String json = "{\"resourceType\":\"Condition\",\"id\":\"c1\","
                + "\"clinicalStatus\":{\"coding\":[{\"code\":\"active\"}]},"
                + "\"code\":{\"text\":\"Hypertension\"},\"onsetDateTime\":\"2025-03-11\"}";
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(raw("Condition", "c1", json)));

        final int written = projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE);

        assertThat(written).isEqualTo(1);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo).save(cap.capture());
        final EhrResource saved = cap.getValue();
        assertThat(saved.getUserId()).isEqualTo(USER);
        assertThat(saved.getPatientId()).isEqualTo(PATIENT);
        assertThat(saved.getSource()).isEqualTo(OracleProperties.SOURCE_ORACLE);
        assertThat(saved.getResourceType()).isEqualTo("Condition");
        assertThat(saved.getResourceFhirId()).isEqualTo("c1");
        assertThat(saved.getStatusValue()).isEqualTo("active");
        assertThat(saved.getTitle()).isEqualTo("Condition: Hypertension");
        assertThat(saved.getOccurredAt()).isEqualTo("2025-03-11");
        assertThat(saved.getContentHash()).startsWith("sha256:");
        assertThat(saved.getPayloadJson()).contains("Hypertension");
    }

    @Test
    void fallsBackToPayloadIdWhenExternalIdMissing() {
        stubOracleSource();
        stubNoExisting();
        final String json = "{\"resourceType\":\"Observation\",\"id\":\"o9\",\"status\":\"final\","
                + "\"code\":{\"text\":\"Weight\"},\"effectiveDateTime\":\"2026-02-02T09:00:00Z\"}";
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(raw("Observation", null, json)));

        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isEqualTo(1);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo).save(cap.capture());
        assertThat(cap.getValue().getResourceFhirId()).isEqualTo("o9");
        assertThat(cap.getValue().getTitle()).isEqualTo("Observation: Weight");
        assertThat(cap.getValue().getOccurredAt()).isEqualTo("2026-02-02T09:00:00Z");
    }

    // --- project: skip / no-op branches -----------------------------------

    @Test
    void skipsUnparseableStatusGatedAndIdlessPayloads() {
        stubOracleSource();
        stubNoExisting();
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(
                        raw("Observation", "bad", "not-json{"),                                   // unparseable
                        raw("Observation", "x", "{\"resourceType\":\"Observation\",\"id\":\"x\","  // status-gated
                                + "\"status\":\"cancelled\",\"code\":{\"text\":\"c\"}}"),
                        raw("Observation", null, "{\"resourceType\":\"Observation\","              // no id anywhere
                                + "\"status\":\"final\"}")));

        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isZero();
        verify(resourceRepo, never()).save(any());
    }

    @Test
    void skipsWhenResourceTypeCannotBeResolved() {
        stubOracleSource();
        // raw.resourceType null AND payload has no resourceType -> type null -> skip.
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(raw(null, "n1", "{\"id\":\"n1\"}")));
        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isZero();
        verify(resourceRepo, never()).save(any());
    }

    // --- project: idempotency + update ------------------------------------

    @Test
    void unchangedContentHashIsIdempotentNoOp() {
        stubOracleSource();
        final String json = "{\"resourceType\":\"Observation\",\"id\":\"o1\",\"status\":\"final\","
                + "\"code\":{\"text\":\"Hgb\"}}";
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(raw("Observation", "o1", json)));
        // Existing row whose hash equals the hash of the canonical payload.
        final EhrResource existing = new EhrResource();
        existing.setId(99L);
        existing.setContentHash(com.careconnect.util.ContentHashUtil.sha256(canonical(json)));
        when(resourceRepo.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
                USER, OracleProperties.SOURCE_ORACLE, "Observation", "o1"))
                .thenReturn(Optional.of(existing));

        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isZero();
        verify(resourceRepo, never()).save(any());
    }

    @Test
    void changedContentUpdatesExistingRow() {
        stubOracleSource();
        final String json = "{\"resourceType\":\"Observation\",\"id\":\"o1\",\"status\":\"final\","
                + "\"code\":{\"text\":\"Hgb\"}}";
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(raw("Observation", "o1", json)));
        final EhrResource existing = new EhrResource();
        existing.setId(99L);
        existing.setContentHash("sha256:stale");
        when(resourceRepo.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
                USER, OracleProperties.SOURCE_ORACLE, "Observation", "o1"))
                .thenReturn(Optional.of(existing));

        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isEqualTo(1);
        verify(resourceRepo).save(existing);
        assertThat(existing.getTitle()).isEqualTo("Observation: Hgb");
    }

    // --- projectForUser ----------------------------------------------------

    @Test
    void projectForUserReturnsZeroWhenNoPatientRow() {
        when(patientRepository.findByUserId(USER)).thenReturn(Optional.empty());
        assertThat(projector.projectForUser(USER)).isZero();
    }

    @Test
    void projectForUserProjectsBothMirrorableSources() {
        final Patient p = new Patient();
        p.setId(PATIENT);
        when(patientRepository.findByUserId(USER)).thenReturn(Optional.of(p));
        stubOracleSource();
        when(sourceRepo.findByCode(MedicareProperties.SOURCE_MEDICARE))
                .thenReturn(Optional.of(source(MEDICARE_SRC_ID, MedicareProperties.SOURCE_MEDICARE)));
        stubNoExisting();
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(raw("Condition", "c1",
                        "{\"resourceType\":\"Condition\",\"id\":\"c1\",\"code\":{\"text\":\"HTN\"}}")));
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, MEDICARE_SRC_ID))
                .thenReturn(List.of(raw("Coverage", "cov1",
                        "{\"resourceType\":\"Coverage\",\"id\":\"cov1\",\"status\":\"active\","
                                + "\"type\":{\"text\":\"Part B\"},\"period\":{\"start\":\"2015-01-01\"}}")));

        assertThat(projector.projectForUser(USER)).isEqualTo(2);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo, org.mockito.Mockito.times(2)).save(cap.capture());
        assertThat(cap.getAllValues()).extracting(EhrResource::getSource)
                .containsExactlyInAnyOrder(OracleProperties.SOURCE_ORACLE, MedicareProperties.SOURCE_MEDICARE);
    }

    // --- title derivation variants (buildTitle / textOf branches) ---------

    @Test
    void titleDerivationCoversTheCodeableAndFallbackForms() {
        stubOracleSource();
        stubNoExisting();
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(
                        // medicationCodeableConcept via coding.display
                        raw("MedicationRequest", "m1", "{\"resourceType\":\"MedicationRequest\",\"id\":\"m1\","
                                + "\"status\":\"active\",\"medicationCodeableConcept\":{\"coding\":[{\"display\":\"Aspirin\"}]}}"),
                        // CarePlan.title (plain string)
                        raw("CarePlan", "cp1", "{\"resourceType\":\"CarePlan\",\"id\":\"cp1\",\"status\":\"active\","
                                + "\"title\":\"Diabetes plan\"}"),
                        // Encounter.type as an ARRAY of CodeableConcept -> first element text
                        raw("Encounter", "e1", "{\"resourceType\":\"Encounter\",\"id\":\"e1\",\"status\":\"finished\","
                                + "\"type\":[{\"text\":\"Office visit\"}],\"period\":{\"start\":\"2026-01-01\"}}"),
                        // bare Coding display (class)
                        raw("Encounter", "e2", "{\"resourceType\":\"Encounter\",\"id\":\"e2\",\"status\":\"finished\","
                                + "\"class\":{\"display\":\"ambulatory\"}}"),
                        // no derivable label -> resourceType only
                        raw("Device", "d1", "{\"resourceType\":\"Device\",\"id\":\"d1\",\"status\":\"active\"}")));

        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isEqualTo(5);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo, org.mockito.Mockito.times(5)).save(cap.capture());
        assertThat(cap.getAllValues()).extracting(EhrResource::getTitle).containsExactly(
                "MedicationRequest: Aspirin",
                "CarePlan: Diabetes plan",
                "Encounter: Office visit",
                "Encounter: ambulatory",
                "Device");
    }

    @Test
    void coversTextOfVariantsAndStringForms() {
        stubOracleSource();
        stubNoExisting();
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(
                        // code as an ARRAY of CodeableConcept -> first element .text
                        raw("Observation", "t1", "{\"resourceType\":\"Observation\",\"id\":\"t1\","
                                + "\"code\":[{\"text\":\"ArrText\"}]}"),
                        // code with coding[].display only (no .text)
                        raw("Observation", "t2", "{\"resourceType\":\"Observation\",\"id\":\"t2\","
                                + "\"code\":{\"coding\":[{\"display\":\"CodingDisp\"}]}}"),
                        // bare Coding .display (no text, no coding[])
                        raw("Observation", "t3", "{\"resourceType\":\"Observation\",\"id\":\"t3\","
                                + "\"code\":{\"display\":\"BareDisp\"}}"),
                        // medicationCodeableConcept via .text
                        raw("MedicationRequest", "t4", "{\"resourceType\":\"MedicationRequest\",\"id\":\"t4\","
                                + "\"medicationCodeableConcept\":{\"text\":\"MedText\"}}"),
                        // CareTeam.name (plain string)
                        raw("CareTeam", "t5", "{\"resourceType\":\"CareTeam\",\"id\":\"t5\",\"name\":\"CareTeamName\"}"),
                        // Goal.description (CodeableConcept)
                        raw("Goal", "t6", "{\"resourceType\":\"Goal\",\"id\":\"t6\","
                                + "\"description\":{\"text\":\"GoalDesc\"}}"),
                        // FamilyMemberHistory.relationship (CodeableConcept) + recordedDate
                        raw("FamilyMemberHistory", "t7", "{\"resourceType\":\"FamilyMemberHistory\",\"id\":\"t7\","
                                + "\"relationship\":{\"text\":\"Mother\"},\"recordedDate\":\"2020-01-01\"}"),
                        // empty code array -> no label -> resourceType only; blank title string ignored
                        raw("Device", "t8", "{\"resourceType\":\"Device\",\"id\":\"t8\",\"type\":[],\"title\":\" \"}")));

        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isEqualTo(8);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo, org.mockito.Mockito.times(8)).save(cap.capture());
        assertThat(cap.getAllValues()).extracting(EhrResource::getTitle).containsExactly(
                "Observation: ArrText",
                "Observation: CodingDisp",
                "Observation: BareDisp",
                "MedicationRequest: MedText",
                "CareTeam: CareTeamName",
                "Goal: GoalDesc",
                "FamilyMemberHistory: Mother",
                "Device");
    }

    @Test
    void coversOccurredAtFieldVariants() {
        stubOracleSource();
        stubNoExisting();
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(
                        raw("MedicationRequest", "a1", "{\"resourceType\":\"MedicationRequest\",\"id\":\"a1\","
                                + "\"code\":{\"text\":\"m\"},\"authoredOn\":\"2024-01-01\"}"),
                        raw("DiagnosticReport", "a2", "{\"resourceType\":\"DiagnosticReport\",\"id\":\"a2\","
                                + "\"code\":{\"text\":\"d\"},\"issued\":\"2024-02-02\"}"),
                        raw("Immunization", "a3", "{\"resourceType\":\"Immunization\",\"id\":\"a3\","
                                + "\"code\":{\"text\":\"i\"},\"date\":\"2024-03-03\"}"),
                        raw("CarePlan", "a4", "{\"resourceType\":\"CarePlan\",\"id\":\"a4\","
                                + "\"title\":\"c\",\"created\":\"2024-05-05\"}"),
                        // effectiveDateTime present but NOT textual -> skipped; falls through to no date
                        raw("Observation", "a5", "{\"resourceType\":\"Observation\",\"id\":\"a5\","
                                + "\"code\":{\"text\":\"o\"},\"effectiveDateTime\":{\"not\":\"textual\"}}")));

        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isEqualTo(5);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo, org.mockito.Mockito.times(5)).save(cap.capture());
        assertThat(cap.getAllValues()).extracting(EhrResource::getOccurredAt).containsExactly(
                "2024-01-01", "2024-02-02", "2024-03-03", "2024-05-05", null);
    }

    @Test
    void blankExternalIdFallsBackToPayloadId() {
        stubOracleSource();
        stubNoExisting();
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(raw("Observation", "   ",
                        "{\"resourceType\":\"Observation\",\"id\":\"real-id\",\"code\":{\"text\":\"x\"}}")));
        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isEqualTo(1);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo).save(cap.capture());
        assertThat(cap.getValue().getResourceFhirId()).isEqualTo("real-id");
    }

    @Test
    void coversRemainingDerivationAndIdBranches() {
        stubOracleSource();
        stubNoExisting();
        when(rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(PATIENT, ORACLE_SRC_ID))
                .thenReturn(List.of(
                        // blank payload -> parse() returns null -> skipped (not saved)
                        raw("Observation", "bp", "   "),
                        // raw.resourceType null but payload carries resourceType -> resolved from payload
                        raw(null, "tp", "{\"resourceType\":\"Immunization\",\"id\":\"tp\",\"code\":{\"text\":\"vax\"}}"),
                        // code is explicit JSON null -> textOf null branch -> title = resourceType only
                        raw("Procedure", "cn", "{\"resourceType\":\"Procedure\",\"id\":\"cn\",\"code\":null}"),
                        // period present without start, no date fields -> occurredAt null
                        raw("Encounter", "pns", "{\"resourceType\":\"Encounter\",\"id\":\"pns\",\"period\":{\"end\":\"2020\"}}"),
                        // coding[0] has no display and no text -> no label -> resourceType only
                        raw("Observation", "cnd", "{\"resourceType\":\"Observation\",\"id\":\"cnd\","
                                + "\"code\":{\"coding\":[{\"code\":\"x\"}]}}"),
                        // blank external id AND blank payload id -> fhirId blank -> skipped (not saved)
                        raw("Observation", "   ", "{\"resourceType\":\"Observation\",\"id\":\"\",\"code\":{\"text\":\"x\"}}")));

        // 4 of 6 are saved (blank payload and blank-id rows are skipped).
        assertThat(projector.projectForSource(USER, PATIENT, OracleProperties.SOURCE_ORACLE)).isEqualTo(4);
        final ArgumentCaptor<EhrResource> cap = ArgumentCaptor.forClass(EhrResource.class);
        verify(resourceRepo, org.mockito.Mockito.times(4)).save(cap.capture());
        assertThat(cap.getAllValues()).extracting(EhrResource::getResourceType)
                .containsExactly("Immunization", "Procedure", "Encounter", "Observation");
        assertThat(cap.getAllValues()).extracting(EhrResource::getTitle)
                .containsExactly("Immunization: vax", "Procedure", "Encounter", "Observation");
        assertThat(cap.getAllValues().get(2).getOccurredAt()).isNull(); // Encounter: period had no start
    }

    private String canonical(final String json) {
        try {
            return mapper.writeValueAsString(mapper.readTree(json));
        } catch (final Exception e) {
            throw new RuntimeException(e);
        }
    }
}
