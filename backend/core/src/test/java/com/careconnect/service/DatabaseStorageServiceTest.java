package com.careconnect.service;

import com.careconnect.model.UserFile;
import com.careconnect.repository.UserFileRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class DatabaseStorageServiceTest {

    @Mock
    private UserFileRepository userFileRepository;

    @InjectMocks
    private DatabaseStorageService storageService;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
    }

    // ========================================================================
    // upload(String, byte[], String)
    // ========================================================================

    @Test
    @DisplayName("upload_validPathWithSlash_extractsFilenameAndSaves")
    void upload_validPathWithSlash_extractsFilenameAndSaves() throws Exception {
        final byte[] content = "file-content".getBytes();
        final UserFile saved = UserFile.builder().id(42L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        final String result = storageService.upload("user_5/photos/image.png", content, "image/png");

        assertEquals("db://files/42", result);

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        final UserFile captured = captor.getValue();
        assertEquals("image.png", captured.getFilename());
        assertEquals("image.png", captured.getOriginalFilename());
        assertEquals("image/png", captured.getContentType());
        assertEquals((long) content.length, captured.getFileSize());
        assertArrayEquals(content, captured.getFileData());
        assertEquals(5L, captured.getOwnerId());
        assertEquals(UserFile.OwnerType.PATIENT, captured.getOwnerType());
        assertEquals(UserFile.FileCategory.OTHER_DOCUMENT, captured.getFileCategory());
        assertEquals(UserFile.StorageType.DATABASE, captured.getStorageType());
        assertEquals("Direct upload via API", captured.getDescription());
    }

    @Test
    @DisplayName("upload_pathWithoutSlash_generatesTimestampedFilename")
    void upload_pathWithoutSlash_generatesTimestampedFilename() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(10L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        final String result = storageService.upload("simple_file", content, "text/plain");

        assertEquals("db://files/10", result);

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        // No slash -> generates "uploaded_file_<timestamp>"
        assertTrue(captor.getValue().getFilename().startsWith("uploaded_file_"));
    }

    @Test
    @DisplayName("upload_pathWithUserPrefix_extractsUserIdCorrectly")
    void upload_pathWithUserPrefix_extractsUserIdCorrectly() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("user_99/somefile.txt", content, "text/plain");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(99L, captor.getValue().getOwnerId());
    }

    @Test
    @DisplayName("upload_pathWithoutUserPrefix_defaultsToUserId1")
    void upload_pathWithoutUserPrefix_defaultsToUserId1() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("some/other/path.txt", content, "text/plain");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(1L, captor.getValue().getOwnerId());
    }

    @Test
    @DisplayName("upload_pathWithUserPrefixInvalidNumber_defaultsToUserId1")
    void upload_pathWithUserPrefixInvalidNumber_defaultsToUserId1() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("user_abc/file.txt", content, "text/plain");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(1L, captor.getValue().getOwnerId());
    }

    @Test
    @DisplayName("upload_pathWithUserPrefixNoSlash_extractsUserIdFromRemainingString")
    void upload_pathWithUserPrefixNoSlash_extractsUserIdFromRemainingString() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("user_77", content, "text/plain");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(77L, captor.getValue().getOwnerId());
    }

    @Test
    @DisplayName("upload_pathContainsPatient_ownerTypeIsPatient")
    void upload_pathContainsPatient_ownerTypeIsPatient() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("patient/file.txt", content, "text/plain");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.OwnerType.PATIENT, captor.getValue().getOwnerType());
    }

    @Test
    @DisplayName("upload_pathContainsCaregiver_ownerTypeIsCaregiver")
    void upload_pathContainsCaregiver_ownerTypeIsCaregiver() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("caregiver/docs/file.txt", content, "text/plain");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.OwnerType.CAREGIVER, captor.getValue().getOwnerType());
    }

    @Test
    @DisplayName("upload_pathContainsFamily_ownerTypeIsFamilyMember")
    void upload_pathContainsFamily_ownerTypeIsFamilyMember() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("family/member/file.txt", content, "text/plain");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.OwnerType.FAMILY_MEMBER, captor.getValue().getOwnerType());
    }

    @Test
    @DisplayName("upload_pathWithNoRecognizedOwnerType_defaultsToPatient")
    void upload_pathWithNoRecognizedOwnerType_defaultsToPatient() throws Exception {
        final byte[] content = "data".getBytes();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.upload("admin/files/report.pdf", content, "application/pdf");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.OwnerType.PATIENT, captor.getValue().getOwnerType());
    }

    @Test
    @DisplayName("upload_repositoryThrowsException_wrapsInRuntimeException")
    void upload_repositoryThrowsException_wrapsInRuntimeException() throws Exception {
        when(userFileRepository.save(any(UserFile.class)))
                .thenThrow(new RuntimeException("DB error"));

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.upload("user_1/file.txt", "data".getBytes(), "text/plain"));
        assertTrue(thrown.getMessage().contains("Failed to upload file to database"));
    }

    // ========================================================================
    // uploadFile(MultipartFile, Long, String, String)
    // ========================================================================

    @Test
    @DisplayName("uploadFile_validFilePatientType_savesCorrectly")
    void uploadFile_validFilePatientType_savesCorrectly() throws IOException {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getOriginalFilename()).thenReturn("report.pdf");
        when(file.getContentType()).thenReturn("application/pdf");
        when(file.getSize()).thenReturn(1024L);
        when(file.getBytes()).thenReturn(new byte[1024]);

        final UserFile saved = UserFile.builder().id(55L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        final String result = storageService.uploadFile(file, 10L, "PATIENT", "MEDICAL_RECORD");

        assertEquals("db://files/55", result);

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        final UserFile captured = captor.getValue();
        assertEquals("report.pdf", captured.getOriginalFilename());
        assertEquals("application/pdf", captured.getContentType());
        assertEquals(1024L, captured.getFileSize());
        assertEquals(10L, captured.getOwnerId());
        assertEquals(UserFile.OwnerType.PATIENT, captured.getOwnerType());
        assertEquals(UserFile.FileCategory.MEDICAL_RECORD, captured.getFileCategory());
        assertEquals(10L, captured.getPatientId()); // PATIENT -> patientId = userId
        assertEquals(UserFile.StorageType.DATABASE, captured.getStorageType());
        assertEquals("Uploaded via web interface", captured.getDescription());
        // Filename should follow pattern: patient_10_MEDICAL_RECORD_<timestamp>.pdf
        assertTrue(captured.getFilename().startsWith("patient_10_MEDICAL_RECORD_"));
        assertTrue(captured.getFilename().endsWith(".pdf"));
    }

    @Test
    @DisplayName("uploadFile_caregiverOwnerType_patientIdIsNull")
    void uploadFile_caregiverOwnerType_patientIdIsNull() throws IOException {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getOriginalFilename()).thenReturn("notes.txt");
        when(file.getContentType()).thenReturn("text/plain");
        when(file.getSize()).thenReturn(256L);
        when(file.getBytes()).thenReturn(new byte[256]);

        final UserFile saved = UserFile.builder().id(60L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        final String result = storageService.uploadFile(file, 20L, "caregiver", "CLINICAL_NOTE");

        assertEquals("db://files/60", result);

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.OwnerType.CAREGIVER, captor.getValue().getOwnerType());
        assertNull(captor.getValue().getPatientId());
    }

    @Test
    @DisplayName("uploadFile_emptyFile_throwsIllegalArgumentExceptionWrappedInRuntimeException")
    void uploadFile_emptyFile_throwsIllegalArgumentExceptionWrappedInRuntimeException() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(true);

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.uploadFile(file, 10L, "PATIENT", "PROFILE"));
        assertTrue(thrown.getMessage().contains("Failed to upload file to database"));
        assertInstanceOf(IllegalArgumentException.class, thrown.getCause());
    }

    @Test
    @DisplayName("uploadFile_getBytesFails_wrapsIOExceptionInRuntimeException")
    void uploadFile_getBytesFails_wrapsIOExceptionInRuntimeException() throws IOException {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getOriginalFilename()).thenReturn("photo.jpg");
        when(file.getContentType()).thenReturn("image/jpeg");
        when(file.getSize()).thenReturn(500L);
        when(file.getBytes()).thenThrow(new IOException("Disk full"));

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.uploadFile(file, 10L, "PATIENT", "PROFILE_IMAGE"));
        assertTrue(thrown.getMessage().contains("Failed to upload file - IO Error"));
    }

    @Test
    @DisplayName("uploadFile_repositorySaveThrows_wrapsInRuntimeException")
    void uploadFile_repositorySaveThrows_wrapsInRuntimeException() throws IOException {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getOriginalFilename()).thenReturn("doc.pdf");
        when(file.getContentType()).thenReturn("application/pdf");
        when(file.getSize()).thenReturn(100L);
        when(file.getBytes()).thenReturn(new byte[100]);
        when(userFileRepository.save(any(UserFile.class)))
                .thenThrow(new IllegalStateException("constraint violation"));

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.uploadFile(file, 10L, "PATIENT", "MEDICAL"));
        assertTrue(thrown.getMessage().contains("Failed to upload file to database"));
    }

    @Test
    @DisplayName("uploadFile_fileWithoutExtension_filenameHasNoExtension")
    void uploadFile_fileWithoutExtension_filenameHasNoExtension() throws IOException {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getOriginalFilename()).thenReturn("readme");
        when(file.getContentType()).thenReturn("text/plain");
        when(file.getSize()).thenReturn(50L);
        when(file.getBytes()).thenReturn(new byte[50]);

        final UserFile saved = UserFile.builder().id(70L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 10L, "PATIENT", "OTHER_DOCUMENT");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertFalse(captor.getValue().getFilename().contains("."));
    }

    @Test
    @DisplayName("uploadFile_nullOriginalFilename_filenameHasNoExtension")
    void uploadFile_nullOriginalFilename_filenameHasNoExtension() throws IOException {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getOriginalFilename()).thenReturn(null);
        when(file.getContentType()).thenReturn("application/octet-stream");
        when(file.getSize()).thenReturn(10L);
        when(file.getBytes()).thenReturn(new byte[10]);

        final UserFile saved = UserFile.builder().id(71L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 10L, "PATIENT", "OTHER_DOCUMENT");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertFalse(captor.getValue().getFilename().contains("."));
    }

    // ========================================================================
    // mapCategoryToEnum (tested via uploadFile)
    // ========================================================================

    @Test
    @DisplayName("uploadFile_categoryProfileImage_mapsToProfileImageEnum")
    void uploadFile_categoryProfileImage_mapsToProfileImageEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "PROFILE_IMAGE");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.PROFILE_IMAGE, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryProfile_mapsToProfileImageEnum")
    void uploadFile_categoryProfile_mapsToProfileImageEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "PROFILE");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.PROFILE_IMAGE, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryMedical_mapsToMedicalRecordEnum")
    void uploadFile_categoryMedical_mapsToMedicalRecordEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "MEDICAL");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.MEDICAL_RECORD, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryMedicalRecord_mapsToMedicalRecordEnum")
    void uploadFile_categoryMedicalRecord_mapsToMedicalRecordEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "MEDICAL_RECORD");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.MEDICAL_RECORD, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryClinicalNote_mapsToClinicalNoteEnum")
    void uploadFile_categoryClinicalNote_mapsToClinicalNoteEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "CLINICAL_NOTE");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.CLINICAL_NOTE, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryClinical_mapsToClinicalNoteEnum")
    void uploadFile_categoryClinical_mapsToClinicalNoteEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "CLINICAL");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.CLINICAL_NOTE, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryPrescription_mapsToPrescriptionEnum")
    void uploadFile_categoryPrescription_mapsToPrescriptionEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "PRESCRIPTION");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.PRESCRIPTION, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryLabResult_mapsToLabResultEnum")
    void uploadFile_categoryLabResult_mapsToLabResultEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "LAB_RESULT");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.LAB_RESULT, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryLab_mapsToLabResultEnum")
    void uploadFile_categoryLab_mapsToLabResultEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "LAB");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.LAB_RESULT, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryInsuranceDocument_mapsToInsuranceDocumentEnum")
    void uploadFile_categoryInsuranceDocument_mapsToInsuranceDocumentEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "INSURANCE_DOCUMENT");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.INSURANCE_DOCUMENT, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryInsurance_mapsToInsuranceDocumentEnum")
    void uploadFile_categoryInsurance_mapsToInsuranceDocumentEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "INSURANCE");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.INSURANCE_DOCUMENT, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryConsentForm_mapsToConsentFormEnum")
    void uploadFile_categoryConsentForm_mapsToConsentFormEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "CONSENT_FORM");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.CONSENT_FORM, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryConsent_mapsToConsentFormEnum")
    void uploadFile_categoryConsent_mapsToConsentFormEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "CONSENT");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.CONSENT_FORM, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryCarePlan_mapsToCarePlanEnum")
    void uploadFile_categoryCarePlan_mapsToCarePlanEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "CARE_PLAN");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.CARE_PLAN, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_categoryCare_mapsToCarePlanEnum")
    void uploadFile_categoryCare_mapsToCarePlanEnum() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 1L, "PATIENT", "CARE");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.CARE_PLAN, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_unknownCategory_throwsIllegalArgumentException")
    void uploadFile_unknownCategory_defaultsToOtherDocument() throws IOException {
        final MultipartFile file = createMockFile();

        assertThrows(IllegalArgumentException.class,
                () -> storageService.uploadFile(file, 1L, "PATIENT", "UNKNOWN_CATEGORY"));
    }

    @Test
    @DisplayName("uploadFile_nullCategory_defaultsToOtherDocument")
    void uploadFile_nullCategory_defaultsToOtherDocument() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        // null category triggers the early return in mapCategoryToEnum
        // Note: This will cause a NullPointerException in generateUniqueFilename
        // because category.toUpperCase() is called there, but mapCategoryToEnum
        // handles null gracefully. The NPE is caught by the outer catch.
        // Actually, looking at the code more carefully, the null goes to
        // mapCategoryToEnum which returns OTHER_DOCUMENT, but the
        // generateUniqueFilename also receives category which is null,
        // and String.format with null just prints "null". So this should work.
        storageService.uploadFile(file, 1L, "PATIENT", null);

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.FileCategory.OTHER_DOCUMENT, captor.getValue().getFileCategory());
    }

    @Test
    @DisplayName("uploadFile_familyMemberOwnerType_patientIdIsNull")
    void uploadFile_familyMemberOwnerType_patientIdIsNull() throws IOException {
        final MultipartFile file = createMockFile();
        final UserFile saved = UserFile.builder().id(1L).build();
        when(userFileRepository.save(any(UserFile.class))).thenReturn(saved);

        storageService.uploadFile(file, 30L, "FAMILY_MEMBER", "OTHER_DOCUMENT");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertEquals(UserFile.OwnerType.FAMILY_MEMBER, captor.getValue().getOwnerType());
        assertNull(captor.getValue().getPatientId());
    }

    // ========================================================================
    // download(String)
    // ========================================================================

    @Test
    @DisplayName("download_validDbPath_returnsFileData")
    void download_validDbPath_returnsFileData() throws Exception {
        final byte[] data = "hello-world".getBytes();
        final UserFile userFile = UserFile.builder()
                .id(42L)
                .fileData(data)
                .fileSize((long) data.length)
                .isActive(true)
                .build();
        when(userFileRepository.findById(42L)).thenReturn(Optional.of(userFile));

        final byte[] result = storageService.download("db://files/42");

        assertArrayEquals(data, result);
    }

    @Test
    @DisplayName("download_numericPath_returnsFileData")
    void download_numericPath_returnsFileData() throws Exception {
        final byte[] data = "content".getBytes();
        final UserFile userFile = UserFile.builder()
                .id(7L)
                .fileData(data)
                .fileSize((long) data.length)
                .isActive(true)
                .build();
        when(userFileRepository.findById(7L)).thenReturn(Optional.of(userFile));

        final byte[] result = storageService.download("7");

        assertArrayEquals(data, result);
    }

    @Test
    @DisplayName("download_fileNotFound_throwsRuntimeException")
    void download_fileNotFound_throwsRuntimeException() throws Exception {
        when(userFileRepository.findById(999L)).thenReturn(Optional.empty());

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.download("db://files/999"));
        assertTrue(thrown.getMessage().contains("Failed to download file from database"));
    }

    @Test
    @DisplayName("download_fileIsInactive_throwsRuntimeException")
    void download_fileIsInactive_throwsRuntimeException() throws Exception {
        final UserFile userFile = UserFile.builder()
                .id(42L)
                .fileData("data".getBytes())
                .isActive(false)
                .build();
        when(userFileRepository.findById(42L)).thenReturn(Optional.of(userFile));

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.download("db://files/42"));
        assertTrue(thrown.getMessage().contains("Failed to download file from database"));
    }

    @Test
    @DisplayName("download_invalidPathFormat_throwsRuntimeException")
    void download_invalidPathFormat_throwsRuntimeException() throws Exception {
        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.download("invalid-path"));
        assertTrue(thrown.getMessage().contains("Failed to download file from database"));
    }

    // ========================================================================
    // getFileUrl(String)
    // ========================================================================

    @Test
    @DisplayName("getFileUrl_validDbPath_returnsApiDownloadUrl")
    void getFileUrl_validDbPath_returnsApiDownloadUrl() throws Exception {
        final String result = storageService.getFileUrl("db://files/42");

        assertEquals("/v1/api/files/42/download", result);
    }

    @Test
    @DisplayName("getFileUrl_numericPath_returnsApiDownloadUrl")
    void getFileUrl_numericPath_returnsApiDownloadUrl() throws Exception {
        final String result = storageService.getFileUrl("100");

        assertEquals("/v1/api/files/100/download", result);
    }

    @Test
    @DisplayName("getFileUrl_invalidPathFormat_returnsOriginalPathAsFallback")
    void getFileUrl_invalidPathFormat_returnsOriginalPathAsFallback() throws Exception {
        final String result = storageService.getFileUrl("not-a-valid-path");

        assertEquals("not-a-valid-path", result);
    }

    // ========================================================================
    // deleteFile(String)
    // ========================================================================

    @Test
    @DisplayName("deleteFile_validPathWithExistingFile_softDeletesFile")
    void deleteFile_validPathWithExistingFile_softDeletesFile() throws Exception {
        final UserFile userFile = UserFile.builder()
                .id(42L)
                .isActive(true)
                .build();
        when(userFileRepository.findById(42L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));

        storageService.deleteFile("db://files/42");

        final ArgumentCaptor<UserFile> captor = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(captor.capture());
        assertFalse(captor.getValue().getIsActive());
    }

    @Test
    @DisplayName("deleteFile_fileNotFound_throwsRuntimeException")
    void deleteFile_fileNotFound_throwsRuntimeException() throws Exception {
        when(userFileRepository.findById(999L)).thenReturn(Optional.empty());

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.deleteFile("db://files/999"));
        assertTrue(thrown.getMessage().contains("Failed to delete file from database"));
    }

    @Test
    @DisplayName("deleteFile_invalidPathFormat_throwsRuntimeException")
    void deleteFile_invalidPathFormat_throwsRuntimeException() throws Exception {
        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.deleteFile("invalid-path"));
        assertTrue(thrown.getMessage().contains("Failed to delete file from database"));
    }

    // ========================================================================
    // listUserFiles(Long, String)
    // ========================================================================

    @Test
    @DisplayName("listUserFiles_userHasFiles_returnsDbPathsList")
    void listUserFiles_userHasFiles_returnsDbPathsList() throws Exception {
        final UserFile file1 = UserFile.builder().id(1L).build();
        final UserFile file2 = UserFile.builder().id(2L).build();
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(10L, UserFile.OwnerType.PATIENT))
                .thenReturn(List.of(file1, file2));

        final List<String> result = storageService.listUserFiles(10L, "PATIENT");

        assertEquals(List.of("db://files/1", "db://files/2"), result);
    }

    @Test
    @DisplayName("listUserFiles_noFiles_returnsEmptyList")
    void listUserFiles_noFiles_returnsEmptyList() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(10L, UserFile.OwnerType.CAREGIVER))
                .thenReturn(Collections.emptyList());

        final List<String> result = storageService.listUserFiles(10L, "CAREGIVER");

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("listUserFiles_invalidUserType_throwsRuntimeException")
    void listUserFiles_invalidUserType_throwsRuntimeException() throws Exception {
        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.listUserFiles(10L, "INVALID_TYPE"));
        assertTrue(thrown.getMessage().contains("Failed to list user files"));
    }

    @Test
    @DisplayName("listUserFiles_repositoryThrows_wrapsInRuntimeException")
    void listUserFiles_repositoryThrows_wrapsInRuntimeException() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(10L, UserFile.OwnerType.PATIENT))
                .thenThrow(new RuntimeException("DB error"));

        final RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> storageService.listUserFiles(10L, "PATIENT"));
        assertTrue(thrown.getMessage().contains("Failed to list user files"));
    }

    @Test
    @DisplayName("listUserFiles_lowercaseUserType_convertsToUppercaseAndWorks")
    void listUserFiles_lowercaseUserType_convertsToUppercaseAndWorks() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(10L, UserFile.OwnerType.FAMILY_MEMBER))
                .thenReturn(List.of(UserFile.builder().id(5L).build()));

        final List<String> result = storageService.listUserFiles(10L, "family_member");

        assertEquals(List.of("db://files/5"), result);
    }

    // ========================================================================
    // extractFileIdFromPath - additional coverage via download
    // ========================================================================

    @Test
    @DisplayName("download_dbFilesPrefixPath_correctlyExtractsId")
    void download_dbFilesPrefixPath_correctlyExtractsId() throws Exception {
        final byte[] data = "test".getBytes();
        final UserFile userFile = UserFile.builder()
                .id(123L)
                .fileData(data)
                .fileSize(4L)
                .isActive(true)
                .build();
        when(userFileRepository.findById(123L)).thenReturn(Optional.of(userFile));

        final byte[] result = storageService.download("db://files/123");

        assertArrayEquals(data, result);
    }

    // ========================================================================
    // Helper method
    // ========================================================================

    private MultipartFile createMockFile() throws IOException {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getOriginalFilename()).thenReturn("test.txt");
        when(file.getContentType()).thenReturn("text/plain");
        when(file.getSize()).thenReturn(100L);
        when(file.getBytes()).thenReturn(new byte[100]);
        return file;
    }
}
