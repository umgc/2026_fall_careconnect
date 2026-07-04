package com.careconnect.model;

import com.careconnect.model.UserFile.FileCategory;
import com.careconnect.model.UserFile.OwnerType;
import com.careconnect.model.UserFile.StorageType;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class UserFileTest {

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final UserFile uf = new UserFile();

        assertThat(uf).isNotNull();
        assertThat(uf.getId()).isNull();
        assertThat(uf.getFilename()).isNull();
        assertThat(uf.getOriginalFilename()).isNull();
        assertThat(uf.getContentType()).isNull();
        assertThat(uf.getFileSize()).isNull();
        assertThat(uf.getFileData()).isNull();
        assertThat(uf.getOwnerId()).isNull();
        assertThat(uf.getOwnerType()).isNull();
        assertThat(uf.getFileCategory()).isNull();
        assertThat(uf.getStorageType()).isEqualTo(StorageType.DATABASE); // @Builder.Default initialises in no-arg ctor
        assertThat(uf.getIsActive()).isTrue();    // @Builder.Default initialises in no-arg ctor
    }

    // ─── Builder defaults ─────────────────────────────────────────────────────

    @Test
    void builder_defaults() throws Exception {
        final UserFile uf = UserFile.builder()
                .filename("test.pdf")
                .originalFilename("original.pdf")
                .fileData(new byte[]{1, 2, 3})
                .ownerId(1L)
                .ownerType(OwnerType.PATIENT)
                .fileCategory(FileCategory.MEDICAL_RECORD)
                .uploadedAt(LocalDateTime.now())
                .build();

        assertThat(uf.getStorageType()).isEqualTo(StorageType.DATABASE);
        assertThat(uf.getIsActive()).isTrue();
    }

    // ─── Builder all fields ───────────────────────────────────────────────────

    @Test
    void builder_allFields() throws Exception {
        final LocalDateTime now = LocalDateTime.now();
        byte[] data = {10, 20, 30};

        final UserFile uf = UserFile.builder()
                .id(1L)
                .filename("file.pdf")
                .originalFilename("original.pdf")
                .contentType("application/pdf")
                .fileSize(1024L)
                .fileData(data)
                .ownerId(5L)
                .ownerType(OwnerType.CAREGIVER)
                .fileCategory(FileCategory.CLINICAL_NOTE)
                .patientId(10L)
                .storageType(StorageType.S3)
                .s3Path("s3://bucket/file.pdf")
                .description("Clinical note for patient")
                .uploadedAt(now)
                .updatedAt(now)
                .isActive(true)
                .build();

        assertThat(uf.getId()).isEqualTo(1L);
        assertThat(uf.getFilename()).isEqualTo("file.pdf");
        assertThat(uf.getOriginalFilename()).isEqualTo("original.pdf");
        assertThat(uf.getContentType()).isEqualTo("application/pdf");
        assertThat(uf.getFileSize()).isEqualTo(1024L);
        assertThat(uf.getFileData()).isEqualTo(data);
        assertThat(uf.getOwnerId()).isEqualTo(5L);
        assertThat(uf.getOwnerType()).isEqualTo(OwnerType.CAREGIVER);
        assertThat(uf.getFileCategory()).isEqualTo(FileCategory.CLINICAL_NOTE);
        assertThat(uf.getPatientId()).isEqualTo(10L);
        assertThat(uf.getStorageType()).isEqualTo(StorageType.S3);
        assertThat(uf.getS3Path()).isEqualTo("s3://bucket/file.pdf");
        assertThat(uf.getDescription()).isEqualTo("Clinical note for patient");
        assertThat(uf.getUploadedAt()).isEqualTo(now);
        assertThat(uf.getUpdatedAt()).isEqualTo(now);
        assertThat(uf.getIsActive()).isTrue();
    }

    // ─── onCreate() ───────────────────────────────────────────────────────────

    @Test
    void onCreate_setsTimestampsAndDefaultsIsActive() throws Exception {
        final UserFile uf = new UserFile();
        uf.setIsActive(null);

        final Method m = UserFile.class.getDeclaredMethod("onCreate");
        m.setAccessible(true);
        m.invoke(uf);

        assertThat(uf.getUploadedAt()).isNotNull();
        assertThat(uf.getUpdatedAt()).isNotNull();
        assertThat(uf.getIsActive()).isTrue();
    }

    @Test
    void onCreate_preservesExistingIsActiveFalse() throws Exception {
        final UserFile uf = new UserFile();
        uf.setIsActive(false);

        final Method m = UserFile.class.getDeclaredMethod("onCreate");
        m.setAccessible(true);
        m.invoke(uf);

        assertThat(uf.getIsActive()).isFalse();
    }

    // ─── onUpdate() ───────────────────────────────────────────────────────────

    @Test
    void onUpdate_refreshesUpdatedAt() throws Exception {
        final UserFile uf = new UserFile();
        uf.setUpdatedAt(LocalDateTime.now().minusDays(1));
        final LocalDateTime before = uf.getUpdatedAt();

        final Method m = UserFile.class.getDeclaredMethod("onUpdate");
        m.setAccessible(true);
        m.invoke(uf);

        assertThat(uf.getUpdatedAt()).isAfter(before);
    }

    // ─── Enum values ──────────────────────────────────────────────────────────

    @Test
    void ownerType_allValues() throws Exception {
        assertThat(OwnerType.values())
                .containsExactly(OwnerType.PATIENT, OwnerType.CAREGIVER,
                        OwnerType.FAMILY_MEMBER, OwnerType.ADMIN);
    }

    @Test
    void fileCategory_allValues() throws Exception {
        // 8 core + 8 employment/home-care intake + EMERGENCY_CONTACT + HIRING_DOCUMENT + OTHER_DOCUMENT
        assertThat(FileCategory.values()).hasSize(19);
        assertThat(FileCategory.valueOf("PROFILE_IMAGE")).isEqualTo(FileCategory.PROFILE_IMAGE);
        assertThat(FileCategory.valueOf("OTHER_DOCUMENT")).isEqualTo(FileCategory.OTHER_DOCUMENT);
        assertThat(FileCategory.valueOf("EMPLOYMENT_APPLICATION"))
                .isEqualTo(FileCategory.EMPLOYMENT_APPLICATION);
        assertThat(FileCategory.valueOf("HIRING_DOCUMENT")).isEqualTo(FileCategory.HIRING_DOCUMENT);
    }

    // ─── fromClientValue(): typed category alignment ──────────────────────────

    @Test
    void fromClientValue_canonicalNames_resolveDirectly() {
        assertThat(FileCategory.fromClientValue("MEDICAL_RECORD")).isEqualTo(FileCategory.MEDICAL_RECORD);
        assertThat(FileCategory.fromClientValue("ONBOARDING_FORM")).isEqualTo(FileCategory.ONBOARDING_FORM);
    }

    @Test
    void fromClientValue_frontendAliases_mapToBackendCategories() {
        // Frontend historically sent these values; they must map to the right backend category.
        assertThat(FileCategory.fromClientValue("MEDICAL_REPORT")).isEqualTo(FileCategory.MEDICAL_RECORD);
        assertThat(FileCategory.fromClientValue("CLINICAL_NOTES")).isEqualTo(FileCategory.CLINICAL_NOTE);
        assertThat(FileCategory.fromClientValue("PROFILE_PICTURE")).isEqualTo(FileCategory.PROFILE_IMAGE);
        assertThat(FileCategory.fromClientValue("INSURANCE")).isEqualTo(FileCategory.INSURANCE_DOCUMENT);
    }

    @Test
    void fromClientValue_isCaseAndSeparatorInsensitive() {
        assertThat(FileCategory.fromClientValue("medical-report")).isEqualTo(FileCategory.MEDICAL_RECORD);
        assertThat(FileCategory.fromClientValue("Onboarding Form")).isEqualTo(FileCategory.ONBOARDING_FORM);
    }

    @Test
    void fromClientValue_blankOrNull_defaultsToOtherDocument() {
        assertThat(FileCategory.fromClientValue(null)).isEqualTo(FileCategory.OTHER_DOCUMENT);
        assertThat(FileCategory.fromClientValue("  ")).isEqualTo(FileCategory.OTHER_DOCUMENT);
    }

    @Test
    void fromClientValue_unknownValue_throwsWithClearMessage() {
        org.assertj.core.api.Assertions
                .assertThatThrownBy(() -> FileCategory.fromClientValue("NOT_A_REAL_CATEGORY"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Invalid file category")
                .hasMessageContaining("NOT_A_REAL_CATEGORY");
    }

    @Test
    void isEmploymentIntake_identifiesHiringAndOnboardingTypes() {
        assertThat(FileCategory.EMPLOYMENT_APPLICATION.isEmploymentIntake()).isTrue();
        assertThat(FileCategory.WORK_AUTHORIZATION.isEmploymentIntake()).isTrue();
        assertThat(FileCategory.MEDICAL_RECORD.isEmploymentIntake()).isFalse();
        assertThat(FileCategory.EMERGENCY_CONTACT.isEmploymentIntake()).isFalse();
        assertThat(FileCategory.HIRING_DOCUMENT.isEmploymentIntake()).isFalse();
        assertThat(FileCategory.EMPLOYMENT_INTAKE).hasSize(8);
    }

    @Test
    void storageType_allValues() throws Exception {
        assertThat(StorageType.values())
                .containsExactly(StorageType.DATABASE, StorageType.S3);
    }
}
