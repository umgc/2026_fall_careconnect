package com.careconnect.repository;

import com.careconnect.model.UserFile;
import com.careconnect.model.UserFile.FileCategory;
import com.careconnect.model.UserFile.OwnerType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Persistence-layer tests for {@link UserFileRepository}, verifying retrieval of
 * files by category, owner, patient and care-circle context — plus the
 * duplicate-filename and soft-delete behaviours relied on by the intake workflow.
 *
 * <p>Uses {@code @DataJpaTest} (JPA slice only) against the in-memory H2 database
 * configured by the {@code test} profile, so the repository's derived-query method
 * names are exercised against a real datasource without booting the whole app.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class UserFileRepositoryIntakeTest {

    @Autowired
    private UserFileRepository repo;

    @BeforeEach
    void clean() {
        repo.deleteAll();
    }

    private UserFile save(String filename, String original, Long ownerId, OwnerType ownerType,
                          FileCategory category, Long patientId, boolean active) {
        UserFile f = UserFile.builder()
                .filename(filename)
                .originalFilename(original)
                .contentType("application/pdf")
                .fileSize(4L)
                .ownerId(ownerId)
                .ownerType(ownerType)
                .fileCategory(category)
                .patientId(patientId)
                .storageType(UserFile.StorageType.DATABASE)
                .isActive(active)
                .build();
        return repo.saveAndFlush(f);
    }

    // ─────────────── Retrieve by owner + category ───────────────

    @Test
    @DisplayName("Repository query: find by owner + category returns only matching active files")
    void findByOwnerAndCategory() {
        save("a", "med.pdf", 1L, OwnerType.PATIENT, FileCategory.MEDICAL_RECORD, 1L, true);
        save("b", "onb.pdf", 1L, OwnerType.PATIENT, FileCategory.ONBOARDING_FORM, 1L, true);

        List<UserFile> medical = repo.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, OwnerType.PATIENT, FileCategory.MEDICAL_RECORD);

        assertThat(medical).hasSize(1);
        assertThat(medical.get(0).getFileCategory()).isEqualTo(FileCategory.MEDICAL_RECORD);
    }

    // ─────────────── Retrieve intake set by owner ───────────────

    @Test
    @DisplayName("Repository query: find intake-category set by owner returns only employment docs")
    void findEmploymentDocsByOwner() {
        save("a", "med.pdf", 2L, OwnerType.CAREGIVER, FileCategory.MEDICAL_RECORD, null, true);
        save("b", "onb.pdf", 2L, OwnerType.CAREGIVER, FileCategory.ONBOARDING_FORM, null, true);
        save("c", "bg.pdf", 2L, OwnerType.CAREGIVER, FileCategory.BACKGROUND_CHECK, null, true);

        List<UserFile> intake = repo.findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(
                2L, OwnerType.CAREGIVER, FileCategory.EMPLOYMENT_INTAKE);

        assertThat(intake).hasSize(2);
        assertThat(intake).allMatch(f -> f.getFileCategory().isEmploymentIntake());
    }

    // ─────────────── Retrieve by patient + category ───────────────

    @Test
    @DisplayName("Repository query: find by patient + category links files to the patient record")
    void findByPatientAndCategory() {
        save("a", "onb.pdf", 1L, OwnerType.PATIENT, FileCategory.ONBOARDING_FORM, 7L, true);
        save("b", "med.pdf", 1L, OwnerType.PATIENT, FileCategory.MEDICAL_RECORD, 7L, true);

        List<UserFile> onboarding = repo.findByPatientIdAndFileCategory(7L, FileCategory.ONBOARDING_FORM);

        assertThat(onboarding).hasSize(1);
        assertThat(onboarding.get(0).getPatientId()).isEqualTo(7L);
    }

    // ─────────────── Care-circle context (intake docs from multiple owners) ───────────────

    @Test
    @DisplayName("Care-circle context: intake docs from patient + caregiver aggregate under the same patient")
    void careCircleAggregatesIntakeAcrossOwners() {
        save("a", "onb.pdf", 1L, OwnerType.PATIENT, FileCategory.ONBOARDING_FORM, 7L, true);   // patient-owned
        save("b", "bg.pdf", 2L, OwnerType.CAREGIVER, FileCategory.BACKGROUND_CHECK, 7L, true); // caregiver-owned
        save("c", "med.pdf", 1L, OwnerType.PATIENT, FileCategory.MEDICAL_RECORD, 7L, true);    // not intake
        save("d", "onb.pdf", 1L, OwnerType.PATIENT, FileCategory.ONBOARDING_FORM, 8L, true);   // different patient

        List<UserFile> careCircle = repo.findByPatientIdAndFileCategoryInAndIsActiveTrue(
                7L, FileCategory.EMPLOYMENT_INTAKE);

        assertThat(careCircle).hasSize(2);
        assertThat(careCircle).extracting(UserFile::getOwnerType)
                .containsExactlyInAnyOrder(OwnerType.PATIENT, OwnerType.CAREGIVER);
        assertThat(careCircle).allMatch(f -> f.getPatientId().equals(7L));
    }

    @Test
    @DisplayName("Files accessible by patient include patient-owned and patient-linked records")
    void findFilesAccessibleByPatient() {
        save("a", "onb.pdf", 1L, OwnerType.PATIENT, FileCategory.ONBOARDING_FORM, 1L, true);
        save("b", "bg.pdf", 2L, OwnerType.CAREGIVER, FileCategory.BACKGROUND_CHECK, 1L, true);
        save("c", "x.pdf", 3L, OwnerType.CAREGIVER, FileCategory.MEDICAL_RECORD, 2L, true); // other patient

        List<UserFile> accessible = repo.findFilesAccessibleByPatient(1L);

        assertThat(accessible).hasSize(2);
    }

    // ─────────────── Duplicate filename behaviour ───────────────

    @Test
    @DisplayName("Duplicate filename: two uploads with the same original name create two distinct records")
    void duplicateFilenameDoesNotOverwrite() {
        UserFile first = save("caregiver_2_BACKGROUND_CHECK_1", "resume.pdf", 2L,
                OwnerType.CAREGIVER, FileCategory.BACKGROUND_CHECK, 1L, true);
        UserFile second = save("caregiver_2_BACKGROUND_CHECK_2", "resume.pdf", 2L,
                OwnerType.CAREGIVER, FileCategory.BACKGROUND_CHECK, 1L, true);

        assertThat(first.getId()).isNotEqualTo(second.getId());

        List<UserFile> all = repo.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                2L, OwnerType.CAREGIVER, FileCategory.BACKGROUND_CHECK);
        assertThat(all).hasSize(2);
        assertThat(all).extracting(UserFile::getOriginalFilename)
                .containsExactly("resume.pdf", "resume.pdf");
    }

    // ─────────────── Soft-delete is excluded ───────────────

    @Test
    @DisplayName("Soft-deleted (isActive=false) files are excluded from active queries")
    void softDeletedExcluded() {
        save("a", "onb.pdf", 1L, OwnerType.PATIENT, FileCategory.ONBOARDING_FORM, 1L, false);

        List<UserFile> active = repo.findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(
                1L, OwnerType.PATIENT, FileCategory.EMPLOYMENT_INTAKE);

        assertThat(active).isEmpty();
    }
}
