package com.careconnect.repository.ehr;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrConflictResolver;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.PatientRepository;
import com.careconnect.testsupport.fixtures.EhrFixtures;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Persistence tests for the EHR identity reconciliation tables against the configured H2 test
 * database (the test JDBC URL maps the PostgreSQL {@code jsonb} domain to TEXT, so the raw
 * payload round-trips).
 *
 * <p>NOTE: the CHECK constraints and the partial unique indexes
 * ({@code uq_ehr_identity_conflict_open}, {@code uq_ehr_source_identity_patient_source}) are
 * PostgreSQL-specific and applied by {@code SchemaPatchRunner} only under
 * {@code isPostgreSql()}. H2 supports neither dollar-quoted blocks nor partial indexes, so
 * they are not exercised here — they are verified against a real PostgreSQL instance.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class EhrIdentityReconciliationRepositoryTest {

    @Autowired
    private EhrSourceRepository sourceRepository;

    @Autowired
    private EhrSourceIdentityRepository snapshotRepository;

    @Autowired
    private EhrIdentityConflictRepository conflictRepository;

    @Autowired
    private PatientRepository patientRepository;

    private Patient patient;
    private EhrSource athena;

    @BeforeEach
    void setUp() {
        patient = patientRepository.save(EhrFixtures.unsavedPatient());
        athena = sourceRepository.save(EhrFixtures.athenaSource());
    }

    @Test
    void sourceAppliesR4AndActiveDefaults() {
        // Arrange / Act — builder omits fhirVersion and active entirely.
        final EhrSource found = sourceRepository.findById(athena.getId()).orElseThrow();

        // Assert — the R4 assumption is persisted, not merely documented.
        assertThat(found.getFhirVersion()).isEqualTo("R4");
        assertThat(found.isActive()).isTrue();
        assertThat(found.getCreatedAt()).isNotNull();
    }

    @Test
    void findsSourceByStableCode() {
        assertThat(sourceRepository.findByCode("ATHENA"))
                .get()
                .extracting(EhrSource::getDisplayName)
                .isEqualTo("athenahealth");
        assertThat(sourceRepository.findByCode("NOPE")).isEmpty();
    }

    @Test
    void snapshotRoundTripsNormalizedDateAndJsonPayload() {
        // Arrange
        final EhrSourceIdentity saved =
                snapshotRepository.save(EhrFixtures.snapshot(patient, athena));

        // Act
        final EhrSourceIdentity found = snapshotRepository.findById(saved.getId()).orElseThrow();

        // Assert — dob is a real date, so 1985-03-02 and 03/02/1985 cannot differ spuriously.
        assertThat(found.getDateOfBirth()).isEqualTo(LocalDate.of(1985, 3, 2));
        assertThat(found.getSourcePatientId()).isEqualTo("a-12345");
        assertThat(found.getSourceUpdatedAt()).isEqualTo(EhrFixtures.SOURCE_UPDATED_AT);
        assertThat(found.getRawPayload()).containsEntry("resourceType", "Patient");
    }

    @Test
    void findsSnapshotByPatientAndSourceUpsertKey() {
        // Arrange
        snapshotRepository.save(EhrFixtures.snapshot(patient, athena));

        // Act / Assert — this pair is what makes an interrupted sync safe to re-run.
        assertThat(snapshotRepository.findByPatientIdAndSourceId(patient.getId(), athena.getId()))
                .isPresent();
        assertThat(snapshotRepository.findByPatientIdAndSourceId(patient.getId(), 999L)).isEmpty();
    }

    @Test
    void reconcilerSeesEverySourceSnapshotForAPatient() {
        // Arrange — two sources disagreeing is the case the reconciler exists for.
        final EhrSource epic = sourceRepository.save(EhrFixtures.epicSource());
        snapshotRepository.save(EhrFixtures.snapshot(patient, athena));
        snapshotRepository.save(EhrFixtures.snapshot(patient, epic));

        // Act
        final List<EhrSourceIdentity> all =
                snapshotRepository.findByPatientId(patient.getId());

        // Assert
        assertThat(all).hasSize(2)
                .extracting(s -> s.getSource().getCode())
                .containsExactlyInAnyOrder("ATHENA", "EPIC");
    }

    @Test
    void conflictDefaultsToPendingWithNoResolution() {
        // Arrange / Act
        final EhrIdentityConflict saved = conflictRepository.save(
                EhrFixtures.pendingConflict(
                        patient, athena, "address_line1", "123 Main St, Apt 4", "456 Oak Ave"));

        // Assert — a fresh conflict must never look partially resolved.
        assertThat(saved.getStatus()).isEqualTo(EhrConflictStatus.PENDING);
        assertThat(saved.getResolvedAt()).isNull();
        assertThat(saved.getResolvedBy()).isNull();
    }

    @Test
    void tracksResolutionPerFieldSoOneFieldCanSettleWhileAnotherWaits() {
        // Arrange — the design's core requirement: name confirmed, address still pending.
        final EhrIdentityConflict name = conflictRepository.save(
                EhrFixtures.pendingConflict(patient, athena, "first_name", "Robert", "Bob"));
        conflictRepository.save(
                EhrFixtures.pendingConflict(
                        patient, athena, "address_line1", "123 Main St", "456 Oak Ave"));

        // Act — resolve only the name.
        name.setStatus(EhrConflictStatus.ACCEPTED);
        name.setResolvedAt(LocalDateTime.of(2026, 9, 12, 11, 0));
        name.setResolvedBy(EhrConflictResolver.PATIENT);
        conflictRepository.save(name);

        // Assert — the two fields hold independent states on the same patient.
        final List<EhrIdentityConflict> pending = conflictRepository
                .findByPatientIdAndStatus(patient.getId(), EhrConflictStatus.PENDING);
        assertThat(pending).hasSize(1)
                .first()
                .extracting(EhrIdentityConflict::getFieldName)
                .isEqualTo("address_line1");

        assertThat(conflictRepository
                .findByPatientIdAndStatus(patient.getId(), EhrConflictStatus.ACCEPTED))
                .hasSize(1);
    }

    @Test
    void pendingCheckDrivesWhetherToPromptAtAll() {
        // Arrange / Assert — nothing pending before any conflict is detected.
        assertThat(conflictRepository
                .existsByPatientIdAndStatus(patient.getId(), EhrConflictStatus.PENDING))
                .isFalse();

        conflictRepository.save(
                EhrFixtures.pendingConflict(patient, athena, "phone", "555-0000", "555-0100"));

        assertThat(conflictRepository
                .existsByPatientIdAndStatus(patient.getId(), EhrConflictStatus.PENDING))
                .isTrue();
    }

    @Test
    void findsTheSingleOpenConflictForAField() {
        // Arrange
        conflictRepository.save(
                EhrFixtures.pendingConflict(patient, athena, "phone", "555-0000", "555-0100"));

        // Act / Assert — a re-sync locates the existing row instead of stacking a duplicate.
        assertThat(conflictRepository.findByPatientIdAndSourceIdAndFieldNameAndStatus(
                        patient.getId(), athena.getId(), "phone", EhrConflictStatus.PENDING))
                .isPresent();
        assertThat(conflictRepository.findByPatientIdAndSourceIdAndFieldNameAndStatus(
                        patient.getId(), athena.getId(), "dob", EhrConflictStatus.PENDING))
                .isEmpty();
    }

    @Test
    void conflictValuesStaySnapshottedWhenTheSourceMovesOn() {
        // Arrange — conflict captured, then the source snapshot changes underneath it.
        final EhrSourceIdentity snapshot =
                snapshotRepository.save(EhrFixtures.snapshot(patient, athena));
        final EhrIdentityConflict conflict = conflictRepository.save(
                EhrFixtures.pendingConflict(
                        patient, athena, "address_line1", "123 Main St", "456 Oak Ave"));

        // Act
        snapshot.setAddressLine1("789 Elm Rd");
        snapshotRepository.saveAndFlush(snapshot);

        // Assert — the confirmation screen still renders the diff it was created from.
        final EhrIdentityConflict found =
                conflictRepository.findById(conflict.getId()).orElseThrow();
        assertThat(found.getIncomingValue()).isEqualTo("456 Oak Ave");
        assertThat(found.getCanonicalValue()).isEqualTo("123 Main St");
    }
}
