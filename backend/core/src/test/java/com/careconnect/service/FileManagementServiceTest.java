package com.careconnect.service;

import com.careconnect.dto.FileUploadResponse;
import com.careconnect.dto.StructuredDocumentEntryDTO;
import com.careconnect.dto.StructuredEntryRequest;
import com.careconnect.dto.UserFileDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.StructuredDocumentEntry;
import com.careconnect.model.User;
import com.careconnect.model.UserFile;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.StructuredDocumentEntryRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.*;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class FileManagementServiceTest {

    @Mock
    private UserFileRepository userFileRepository;
    @Mock
    private StructuredDocumentEntryRepository structuredEntryRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private DatabaseStorageService databaseStorageService;
    @Mock
    private DocumentComplianceService documentComplianceService;
    @Mock
    private com.careconnect.indexing.IndexingEventEmitter indexingEventEmitter;
    @Mock
    private com.careconnect.service.ai.indexing.RetrievalIndexService retrievalIndexService;
    @Mock
    private DocumentProcessingService documentProcessingService;
    @Mock
    private S3StorageService s3StorageService;
    @Mock
    private com.careconnect.service.ai.ask.AskAiDocumentOcrService askAiDocumentOcrService;
    @Mock
    private MultipartFile multipartFile;

    private FileManagementService fileManagementService;

    private UserFile userFile;
    private User user;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        fileManagementService = new FileManagementService(
                userFileRepository, structuredEntryRepository, userRepository, patientRepository,
                databaseStorageService, documentComplianceService, indexingEventEmitter, retrievalIndexService, documentProcessingService, s3StorageService, askAiDocumentOcrService);
        ReflectionTestUtils.setField(fileManagementService, "defaultStorageType", "database");
        ReflectionTestUtils.setField(fileManagementService, "useS3ForNewFiles", false);

        user = new User();
        user.setId(1L);
        user.setEmail("user@test.com");

        userFile = UserFile.builder()
                .id(10L)
                .filename("patient_1_medical_123.pdf")
                .originalFilename("report.pdf")
                .contentType("application/pdf")
                .fileSize(1024L)
                .ownerId(1L)
                .ownerType(UserFile.OwnerType.PATIENT)
                .fileCategory(UserFile.FileCategory.MEDICAL_RECORD)
                .patientId(1L)
                .storageType(UserFile.StorageType.DATABASE)
                .description("Test file")
                .isActive(true)
                .build();
    }

    // uploadFile tests

    @Test
    @DisplayName("uploadFile - database storage with existing file - updates description and returns response")
    void uploadFile_databaseStorageExistingFile_updatesAndReturnsResponse() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl("db://files/10")).thenReturn("http://localhost/files/10");

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "Test description", 1L);

        assertNotNull(result);
        assertEquals(10L, result.getFileId());
        assertEquals("File uploaded successfully", result.getMessage());
        verify(databaseStorageService).uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD"));
    }

    @Test
    @DisplayName("uploadFile - database storage file not found in DB - saves new record")
    void uploadFile_databaseStorageFileNotFound_savesNewRecord() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("db://files/99");
        when(userFileRepository.findById(99L)).thenReturn(Optional.empty());
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "desc", 1L);

        assertNotNull(result);
        verify(userFileRepository, times(1)).save(any(UserFile.class));
    }

    @Test
    @DisplayName("uploadFile - S3 storage enabled - uses S3 service")
    void uploadFile_s3StorageEnabled_usesS3Service() throws Exception {
        ReflectionTestUtils.setField(fileManagementService, "useS3ForNewFiles", true);

        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(s3StorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("s3://bucket/files/report.pdf");
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(s3StorageService.getFileUrl("s3://bucket/files/report.pdf")).thenReturn("https://s3/report.pdf");

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "desc", 1L);

        assertNotNull(result);
        verify(s3StorageService).uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD"));
    }

    @Test
    @DisplayName("uploadFile - S3 enabled but null s3Service - falls back to database")
    void uploadFile_s3EnabledNullService_fallsBackToDatabase() throws Exception {
        final FileManagementService serviceNoS3 = new FileManagementService(
                userFileRepository, structuredEntryRepository, userRepository, patientRepository,
                databaseStorageService, documentComplianceService, indexingEventEmitter, retrievalIndexService, documentProcessingService, null, askAiDocumentOcrService);
        ReflectionTestUtils.setField(serviceNoS3, "defaultStorageType", "database");
        ReflectionTestUtils.setField(serviceNoS3, "useS3ForNewFiles", true);

        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final FileUploadResponse result = serviceNoS3.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "desc", 1L);

        assertNotNull(result);
        verify(databaseStorageService).uploadFile(any(), anyLong(), anyString(), anyString());
    }

    @Test
    @DisplayName("uploadFile - empty file - throws RuntimeException wrapping IllegalArgumentException")
    void uploadFile_emptyFile_throwsRuntimeException() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(true);

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> fileManagementService.uploadFile(multipartFile, 1L, "PATIENT", "MEDICAL", "desc", 1L));
        assertTrue(ex.getMessage().contains("File is empty"));
    }

    @Test
    @DisplayName("uploadFile - file too large - throws RuntimeException")
    void uploadFile_fileTooLarge_throwsRuntimeException() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(20L * 1024 * 1024); // 20MB

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> fileManagementService.uploadFile(multipartFile, 1L, "PATIENT", "MEDICAL", "desc", 1L));
        assertTrue(ex.getMessage().contains("File size exceeds"));
    }

    @Test
    @DisplayName("uploadFile - null content type - throws RuntimeException")
    void uploadFile_nullContentType_throwsRuntimeException() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn(null);

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> fileManagementService.uploadFile(multipartFile, 1L, "PATIENT", "MEDICAL", "desc", 1L));
        assertTrue(ex.getMessage().contains("content type"));
    }

    @Test
    @DisplayName("uploadFile - profile image category - updates user profile image")
    void uploadFile_profileImageCategory_updatesUserProfileImage() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("image/png");
        when(multipartFile.getOriginalFilename()).thenReturn("avatar.png");
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("PROFILE_IMAGE")))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));

        fileManagementService.uploadFile(multipartFile, 1L, "PATIENT", "PROFILE_IMAGE", "avatar", 1L);

        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("uploadFile - profile image with S3 enabled - uses S3 URL for profile")
    void uploadFile_profileImageWithS3_usesS3UrlForProfile() throws Exception {
        ReflectionTestUtils.setField(fileManagementService, "useS3ForNewFiles", true);

        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("image/png");
        when(multipartFile.getOriginalFilename()).thenReturn("avatar.png");
        when(s3StorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("PROFILE_IMAGE")))
                .thenReturn("s3://bucket/avatar.png");
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(s3StorageService.getFileUrl("s3://bucket/avatar.png")).thenReturn("https://s3/avatar.png");
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));

        fileManagementService.uploadFile(multipartFile, 1L, "PATIENT", "PROFILE_IMAGE", "avatar", 1L);

        verify(s3StorageService, atLeastOnce()).getFileUrl(anyString());
        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("uploadFile - profile image update user not found - does not throw")
    void uploadFile_profileImageUserNotFound_doesNotThrow() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("image/png");
        when(multipartFile.getOriginalFilename()).thenReturn("avatar.png");
        when(databaseStorageService.uploadFile(any(), anyLong(), anyString(), anyString()))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");
        when(userRepository.findById(1L)).thenReturn(Optional.empty());

        assertDoesNotThrow(() -> fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "PROFILE_IMAGE", "avatar", 1L));
    }

    @Test
    @DisplayName("uploadFile - null patientId with PATIENT userType - determines patientId from user")
    void uploadFile_nullPatientIdPatientUserType_determinesPatientId() throws Exception {
        final Patient patient = Patient.builder().id(5L).build();
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(databaseStorageService.uploadFile(any(), anyLong(), anyString(), anyString()))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(patientRepository.findByUser(user)).thenReturn(Optional.of(patient));

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "desc", null);

        assertNotNull(result);
    }

    @Test
    @DisplayName("uploadFile - null patientId with CAREGIVER userType - patientId stays null")
    void uploadFile_nullPatientIdCaregiverUserType_patientIdStaysNull() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(databaseStorageService.uploadFile(any(), anyLong(), anyString(), anyString()))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "CAREGIVER", "MEDICAL_RECORD", "desc", null);

        assertNotNull(result);
    }

    @Test
    @DisplayName("uploadFile - null originalFilename - generates filename with empty extension")
    void uploadFile_nullOriginalFilename_generatesFilenameWithEmptyExtension() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/octet-stream");
        when(multipartFile.getOriginalFilename()).thenReturn(null);
        when(databaseStorageService.uploadFile(any(), anyLong(), anyString(), anyString()))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "desc", 1L);

        assertNotNull(result);
    }

    // getFile tests

    @Test
    @DisplayName("getFile - active file exists - returns DTO")
    void getFile_activeFileExists_returnsDTO() throws Exception {
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(databaseStorageService.getFileUrl("db://files/10")).thenReturn("http://localhost/files/10");

        final Optional<UserFileDTO> result = fileManagementService.getFile(10L);

        assertTrue(result.isPresent());
        assertEquals(10L, result.get().getId());
        assertEquals("report.pdf", result.get().getOriginalFilename());
    }

    @Test
    @DisplayName("getFile - file not found - returns empty")
    void getFile_fileNotFound_returnsEmpty() throws Exception {
        when(userFileRepository.findById(99L)).thenReturn(Optional.empty());

        final Optional<UserFileDTO> result = fileManagementService.getFile(99L);

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getFile - inactive file - returns empty")
    void getFile_inactiveFile_returnsEmpty() throws Exception {
        userFile.setIsActive(false);
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));

        final Optional<UserFileDTO> result = fileManagementService.getFile(10L);

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getFile - S3 file with s3Service available - returns S3 URL")
    void getFile_s3FileWithS3Service_returnsS3Url() throws Exception {
        userFile.setStorageType(UserFile.StorageType.S3);
        userFile.setS3Path("s3://bucket/report.pdf");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(s3StorageService.getFileUrl("s3://bucket/report.pdf")).thenReturn("https://s3/report.pdf");

        final Optional<UserFileDTO> result = fileManagementService.getFile(10L);

        assertTrue(result.isPresent());
        assertEquals("https://s3/report.pdf", result.get().getFileUrl());
    }

    @Test
    @DisplayName("getFile - S3 file with null s3Service - returns unavailable URL")
    void getFile_s3FileNullS3Service_returnsUnavailableUrl() throws Exception {
        final FileManagementService serviceNoS3 = new FileManagementService(
                userFileRepository, structuredEntryRepository, userRepository, patientRepository,
                databaseStorageService, documentComplianceService, indexingEventEmitter, retrievalIndexService, documentProcessingService, null, askAiDocumentOcrService);
        ReflectionTestUtils.setField(serviceNoS3, "defaultStorageType", "database");
        ReflectionTestUtils.setField(serviceNoS3, "useS3ForNewFiles", false);

        userFile.setStorageType(UserFile.StorageType.S3);
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));

        final Optional<UserFileDTO> result = serviceNoS3.getFile(10L);

        assertTrue(result.isPresent());
        assertEquals("unavailable://s3-service-not-configured", result.get().getFileUrl());
    }

    // downloadFile tests

    @Test
    @DisplayName("downloadFile - database file - returns file data")
    void downloadFile_databaseFile_returnsFileData() throws Exception {
        userFile.setFileData(new byte[]{1, 2, 3});
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));

        final byte[] result = fileManagementService.downloadFile(10L);

        assertArrayEquals(new byte[]{1, 2, 3}, result);
    }

    @Test
    @DisplayName("downloadFile - S3 file - delegates to S3 service")
    void downloadFile_s3File_delegatesToS3Service() throws Exception {
        userFile.setStorageType(UserFile.StorageType.S3);
        userFile.setS3Path("s3://bucket/report.pdf");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(s3StorageService.download("s3://bucket/report.pdf")).thenReturn(new byte[]{4, 5, 6});

        final byte[] result = fileManagementService.downloadFile(10L);

        assertArrayEquals(new byte[]{4, 5, 6}, result);
    }

    @Test
    @DisplayName("downloadFile - S3 file with null S3 service - throws RuntimeException")
    void downloadFile_s3FileNullS3Service_throwsRuntimeException() throws Exception {
        final FileManagementService serviceNoS3 = new FileManagementService(
                userFileRepository, structuredEntryRepository, userRepository, patientRepository,
                databaseStorageService, documentComplianceService, indexingEventEmitter, retrievalIndexService, documentProcessingService, null, askAiDocumentOcrService);
        ReflectionTestUtils.setField(serviceNoS3, "defaultStorageType", "database");
        ReflectionTestUtils.setField(serviceNoS3, "useS3ForNewFiles", false);

        userFile.setStorageType(UserFile.StorageType.S3);
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> serviceNoS3.downloadFile(10L));
        assertTrue(ex.getMessage().contains("S3 storage service not available"));
    }

    @Test
    @DisplayName("downloadFile - file not found - throws RuntimeException")
    void downloadFile_fileNotFound_throwsRuntimeException() throws Exception {
        when(userFileRepository.findById(99L)).thenReturn(Optional.empty());

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> fileManagementService.downloadFile(99L));
        assertTrue(ex.getMessage().contains("File not found"));
    }

    @Test
    @DisplayName("downloadFile - inactive file - throws RuntimeException")
    void downloadFile_inactiveFile_throwsRuntimeException() throws Exception {
        userFile.setIsActive(false);
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> fileManagementService.downloadFile(10L));
        assertTrue(ex.getMessage().contains("File not found"));
    }

    // listUserFiles tests

    @Test
    @DisplayName("listUserFiles - with category - filters by category")
    void listUserFiles_withCategory_filtersByCategory() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.MEDICAL_RECORD))
                .thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "MEDICAL_RECORD");

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("listUserFiles - null category - returns all files for user")
    void listUserFiles_nullCategory_returnsAllFilesForUser() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(1L, UserFile.OwnerType.PATIENT))
                .thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", null);

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("listUserFiles - empty category - returns all files for user")
    void listUserFiles_emptyCategory_returnsAllFilesForUser() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(1L, UserFile.OwnerType.PATIENT))
                .thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "");

        assertEquals(1, result.size());
    }

    // listFilesForPatient tests

    @Test
    @DisplayName("listFilesForPatient - with category - filters by category")
    void listFilesForPatient_withCategory_filtersByCategory() throws Exception {
        when(userFileRepository.findByPatientIdAndFileCategory(1L, UserFile.FileCategory.MEDICAL_RECORD))
                .thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listFilesForPatient(1L, "MEDICAL_RECORD");

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("listFilesForPatient - null category - returns all accessible files")
    void listFilesForPatient_nullCategory_returnsAllAccessibleFiles() throws Exception {
        when(userFileRepository.findFilesAccessibleByPatient(1L)).thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listFilesForPatient(1L, null);

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("listFilesForPatient - empty category - returns all accessible files")
    void listFilesForPatient_emptyCategory_returnsAllAccessibleFiles() throws Exception {
        when(userFileRepository.findFilesAccessibleByPatient(1L)).thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listFilesForPatient(1L, "");

        assertEquals(1, result.size());
    }

    // listFilesForCaregiverPatient tests

    @Test
    @DisplayName("listFilesForCaregiverPatient - with category - filters by category")
    void listFilesForCaregiverPatient_withCategory_filtersByCategory() throws Exception {
        when(userFileRepository.findByPatientIdAndFileCategory(1L, UserFile.FileCategory.PRESCRIPTION))
                .thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listFilesForCaregiverPatient(1L, "PRESCRIPTION");

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("listFilesForCaregiverPatient - null category - returns all caregiver accessible files")
    void listFilesForCaregiverPatient_nullCategory_returnsAllCaregiverAccessibleFiles() throws Exception {
        when(userFileRepository.findFilesAccessibleByCaregiverForPatient(1L)).thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listFilesForCaregiverPatient(1L, null);

        assertEquals(1, result.size());
    }

    // deleteFile tests

    @Test
    @DisplayName("deleteFile - existing file - soft deletes file and de-indexes")
    void deleteFile_existingFile_softDeletesFile() throws Exception {
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));

        fileManagementService.deleteFile(10L, 1L);

        assertFalse(userFile.getIsActive());
        verify(retrievalIndexService).removeIndexedSource(
                1L, "10", com.careconnect.service.ai.retrieval.RetrievalRecordType.UPLOADED_DOCUMENT);
        verify(userFileRepository).save(userFile);
    }

    @Test
    @DisplayName("deleteFile - profile image - clears user profile image URL")
    void deleteFile_profileImage_clearsUserProfileImageUrl() throws Exception {
        userFile.setFileCategory(UserFile.FileCategory.PROFILE_IMAGE);
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));

        fileManagementService.deleteFile(10L, 1L);

        assertFalse(userFile.getIsActive());
        assertNull(user.getProfileImageUrl());
        verify(userRepository).save(user);
    }

    @Test
    @DisplayName("deleteFile - profile image user not found - does not throw")
    void deleteFile_profileImageUserNotFound_doesNotThrow() throws Exception {
        userFile.setFileCategory(UserFile.FileCategory.PROFILE_IMAGE);
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userRepository.findById(1L)).thenReturn(Optional.empty());

        assertDoesNotThrow(() -> fileManagementService.deleteFile(10L, 1L));
    }

    @Test
    @DisplayName("deleteFile - file not found - throws RuntimeException")
    void deleteFile_fileNotFound_throwsRuntimeException() throws Exception {
        when(userFileRepository.findById(99L)).thenReturn(Optional.empty());

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> fileManagementService.deleteFile(99L, 1L));
        assertTrue(ex.getMessage().contains("File not found"));
    }

    // getUserProfileImage tests

    @Test
    @DisplayName("getUserProfileImage - profile image exists - returns DTO")
    void getUserProfileImage_profileImageExists_returnsDTO() throws Exception {
        when(userFileRepository.findFirstByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.PROFILE_IMAGE))
                .thenReturn(Optional.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final Optional<UserFileDTO> result = fileManagementService.getUserProfileImage(1L, "PATIENT");

        assertTrue(result.isPresent());
    }

    @Test
    @DisplayName("getUserProfileImage - no profile image - returns empty")
    void getUserProfileImage_noProfileImage_returnsEmpty() throws Exception {
        when(userFileRepository.findFirstByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.PROFILE_IMAGE))
                .thenReturn(Optional.empty());

        final Optional<UserFileDTO> result = fileManagementService.getUserProfileImage(1L, "PATIENT");

        assertTrue(result.isEmpty());
    }

    // mapCategoryToEnum tests (tested indirectly)

    @Test
    @DisplayName("listUserFiles - PROFILE category - maps to PROFILE_IMAGE")
    void listUserFiles_profileCategory_mapsToProfileImage() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.PROFILE_IMAGE))
                .thenReturn(List.of(userFile));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "PROFILE");

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("listUserFiles - CLINICAL category - maps to CLINICAL_NOTE")
    void listUserFiles_clinicalCategory_mapsToClinicalNote() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.CLINICAL_NOTE))
                .thenReturn(List.of());
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "CLINICAL");

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("listUserFiles - LAB category - maps to LAB_RESULT")
    void listUserFiles_labCategory_mapsToLabResult() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.LAB_RESULT))
                .thenReturn(List.of());

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "LAB");

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("listUserFiles - INSURANCE category - maps to INSURANCE_DOCUMENT")
    void listUserFiles_insuranceCategory_mapsToInsuranceDocument() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.INSURANCE_DOCUMENT))
                .thenReturn(List.of());

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "INSURANCE");

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("listUserFiles - CONSENT category - maps to CONSENT_FORM")
    void listUserFiles_consentCategory_mapsToConsentForm() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.CONSENT_FORM))
                .thenReturn(List.of());

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "CONSENT");

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("listUserFiles - CARE category - maps to CARE_PLAN")
    void listUserFiles_careCategory_mapsToCarePlan() throws Exception {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                1L, UserFile.OwnerType.PATIENT, UserFile.FileCategory.CARE_PLAN))
                .thenReturn(List.of());

        final List<UserFileDTO> result = fileManagementService.listUserFiles(1L, "PATIENT", "CARE");

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("listUserFiles - unknown category - throws IllegalArgumentException")
    void listUserFiles_unknownCategory_throwsIllegalArgument() throws Exception {
        // Since the typed category alignment (#152), fromClientValue rejects
        // unknown values instead of silently defaulting to OTHER_DOCUMENT.
        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.listUserFiles(1L, "PATIENT", "RANDOM"));
        assertTrue(ex.getMessage().contains("Invalid file category"));
    }

    // Structured form entry tests

    private UserFile intakeFile() {
        return UserFile.builder()
                .id(20L)
                .filename("caregiver_2_certification_123.pdf")
                .originalFilename("cpr-card.pdf")
                .contentType("application/pdf")
                .fileSize(2048L)
                .ownerId(2L)
                .ownerType(UserFile.OwnerType.CAREGIVER)
                .fileCategory(UserFile.FileCategory.CERTIFICATION)
                .storageType(UserFile.StorageType.DATABASE)
                .isActive(true)
                .build();
    }

    private Map<String, String> certificationFields() {
        return Map.of(
                "certificationName", "CPR / First Aid",
                "holderName", "Jane Doe",
                "issuingAuthority", "Red Cross",
                "issueDate", "2026-01-15");
    }

    @Test
    @DisplayName("createStructuredEntry - valid request - saves entry linked to file")
    void createStructuredEntry_validRequest_savesEntryLinkedToFile() {
        final UserFile file = intakeFile();
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.empty());
        when(structuredEntryRepository.save(any(StructuredDocumentEntry.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/20");

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(certificationFields())
                .build();

        final StructuredDocumentEntryDTO result =
                fileManagementService.createStructuredEntry(20L, request, 2L);

        assertEquals(20L, result.getFileId());
        assertEquals("CERTIFICATION", result.getDocumentType());
        assertEquals(2L, result.getEmployeeUserId());
        assertEquals("cpr-card.pdf", result.getOriginalFilename());
        assertEquals("CPR / First Aid", result.getFields().get("certificationName"));
        verify(structuredEntryRepository).save(any(StructuredDocumentEntry.class));
    }

    @Test
    @DisplayName("createStructuredEntry - no patient or employee context - throws")
    void createStructuredEntry_noContext_throws() {
        final UserFile file = intakeFile();
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.empty());

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .fields(certificationFields())
                .build();

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.createStructuredEntry(20L, request, 2L));
        assertTrue(ex.getMessage().contains("patient or employee context"));
        verify(structuredEntryRepository, never()).save(any());
    }

    @Test
    @DisplayName("createStructuredEntry - missing required fields - throws with field names")
    void createStructuredEntry_missingRequiredFields_throwsWithFieldNames() {
        final UserFile file = intakeFile();
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.empty());

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(Map.of("certificationName", "CPR", "holderName", "  "))
                .build();

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.createStructuredEntry(20L, request, 2L));
        assertTrue(ex.getMessage().contains("holderName"));
        assertTrue(ex.getMessage().contains("issueDate"));
        assertTrue(ex.getMessage().contains("issuingAuthority"));
        verify(structuredEntryRepository, never()).save(any());
    }

    @Test
    @DisplayName("createStructuredEntry - unsupported document type - throws")
    void createStructuredEntry_unsupportedDocumentType_throws() {
        final UserFile file = intakeFile();
        file.setFileCategory(UserFile.FileCategory.LAB_RESULT);
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.empty());

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(certificationFields())
                .build();

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.createStructuredEntry(20L, request, 2L));
        assertTrue(ex.getMessage().contains("does not support structured entries"));
    }

    @Test
    @DisplayName("createStructuredEntry - entry already exists for file - throws")
    void createStructuredEntry_entryAlreadyExists_throws() {
        final UserFile file = intakeFile();
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.of(StructuredDocumentEntry.builder().id(5L).userFileId(20L).build()));

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(certificationFields())
                .build();

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.createStructuredEntry(20L, request, 2L));
        assertTrue(ex.getMessage().contains("already exists"));
    }

    @Test
    @DisplayName("createStructuredEntry - uploaded file missing - throws, preventing orphan records")
    void createStructuredEntry_fileMissing_throwsPreventingOrphans() {
        when(userFileRepository.findById(99L)).thenReturn(Optional.empty());

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(certificationFields())
                .build();

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.createStructuredEntry(99L, request, 2L));
        assertTrue(ex.getMessage().contains("File not found"));
        verify(structuredEntryRepository, never()).save(any());
    }

    @Test
    @DisplayName("createStructuredEntry - uploaded file soft-deleted - throws, preventing orphan records")
    void createStructuredEntry_inactiveFile_throwsPreventingOrphans() {
        final UserFile file = intakeFile();
        file.setIsActive(false);
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(certificationFields())
                .build();

        assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.createStructuredEntry(20L, request, 2L));
        verify(structuredEntryRepository, never()).save(any());
    }

    @Test
    @DisplayName("updateStructuredEntry - valid request - re-validates and saves")
    void updateStructuredEntry_validRequest_revalidatesAndSaves() {
        final UserFile file = intakeFile();
        final StructuredDocumentEntry existing = StructuredDocumentEntry.builder()
                .id(5L)
                .userFileId(20L)
                .documentType(UserFile.FileCategory.CERTIFICATION)
                .employeeUserId(2L)
                .fieldsJson("{}")
                .isActive(true)
                .build();
        when(structuredEntryRepository.findById(5L)).thenReturn(Optional.of(existing));
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.save(any(StructuredDocumentEntry.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/20");

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .fields(certificationFields())
                .build();

        final StructuredDocumentEntryDTO result =
                fileManagementService.updateStructuredEntry(5L, request);

        assertEquals(20L, result.getFileId());
        assertEquals(2L, result.getEmployeeUserId());
        assertEquals("Red Cross", result.getFields().get("issuingAuthority"));
    }

    @Test
    @DisplayName("updateStructuredEntry - missing required fields - throws")
    void updateStructuredEntry_missingRequiredFields_throws() {
        final StructuredDocumentEntry existing = StructuredDocumentEntry.builder()
                .id(5L)
                .userFileId(20L)
                .documentType(UserFile.FileCategory.CERTIFICATION)
                .employeeUserId(2L)
                .fieldsJson("{}")
                .isActive(true)
                .build();
        when(structuredEntryRepository.findById(5L)).thenReturn(Optional.of(existing));
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(intakeFile()));

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .fields(Map.of())
                .build();

        assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.updateStructuredEntry(5L, request));
        verify(structuredEntryRepository, never()).save(any());
    }

    @Test
    @DisplayName("updateStructuredEntry - keeps the original file association intact")
    void updateStructuredEntry_preservesFileAssociation() {
        final StructuredDocumentEntry existing = StructuredDocumentEntry.builder()
                .id(5L)
                .userFileId(20L)
                .documentType(UserFile.FileCategory.CERTIFICATION)
                .employeeUserId(2L)
                .fieldsJson("{}")
                .isActive(true)
                .build();
        when(structuredEntryRepository.findById(5L)).thenReturn(Optional.of(existing));
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(intakeFile()));
        when(structuredEntryRepository.save(any(StructuredDocumentEntry.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/20");

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .fields(certificationFields())
                .build();

        final StructuredDocumentEntryDTO result =
                fileManagementService.updateStructuredEntry(5L, request);

        final ArgumentCaptor<StructuredDocumentEntry> saved =
                ArgumentCaptor.forClass(StructuredDocumentEntry.class);
        verify(structuredEntryRepository).save(saved.capture());
        assertEquals(20L, saved.getValue().getUserFileId());
        assertEquals(20L, result.getFileId());
        assertEquals("cpr-card.pdf", result.getOriginalFilename());
    }

    @Test
    @DisplayName("getStructuredEntryForFile - entry exists - returns DTO with linked file")
    void getStructuredEntryForFile_entryExists_returnsDTOWithLinkedFile() {
        final StructuredDocumentEntry existing = StructuredDocumentEntry.builder()
                .id(5L)
                .userFileId(20L)
                .documentType(UserFile.FileCategory.CERTIFICATION)
                .employeeUserId(2L)
                .fieldsJson("{\"certificationName\":\"CPR\"}")
                .isActive(true)
                .build();
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.of(existing));
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(intakeFile()));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/20");

        final Optional<StructuredDocumentEntryDTO> result =
                fileManagementService.getStructuredEntryForFile(20L);

        assertTrue(result.isPresent());
        assertEquals("cpr-card.pdf", result.get().getOriginalFilename());
        assertEquals("CPR", result.get().getFields().get("certificationName"));
    }

    @Test
    @DisplayName("getStructuredEntryForFile - no entry - returns empty")
    void getStructuredEntryForFile_noEntry_returnsEmpty() {
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.empty());

        assertTrue(fileManagementService.getStructuredEntryForFile(20L).isEmpty());
    }

    // Compliance tracking hooks

    @Test
    @DisplayName("uploadFile - notifies compliance tracking with the saved file and uploader")
    void uploadFile_notifiesComplianceTracking() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(databaseStorageService.uploadFile(any(), anyLong(), anyString(), anyString()))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenReturn(userFile);
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        fileManagementService.uploadFile(multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "desc", 1L);

        verify(documentComplianceService).recordDocumentUploaded(userFile, 1L);
    }

    @Test
    @DisplayName("createStructuredEntry - notifies compliance tracking with the saved entry")
    void createStructuredEntry_notifiesComplianceTracking() {
        final UserFile file = intakeFile();
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.empty());
        when(structuredEntryRepository.save(any(StructuredDocumentEntry.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/20");

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(certificationFields())
                .build();

        fileManagementService.createStructuredEntry(20L, request, 2L);

        verify(documentComplianceService)
                .recordStructuredEntrySaved(any(StructuredDocumentEntry.class), eq(file), eq(2L));
    }

    @Test
    @DisplayName("createStructuredEntry - validation failure - compliance tracking is never notified")
    void createStructuredEntry_validationFails_complianceNotNotified() {
        final UserFile file = intakeFile();
        when(userFileRepository.findById(20L)).thenReturn(Optional.of(file));
        when(structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(20L))
                .thenReturn(Optional.empty());

        final StructuredEntryRequest request = StructuredEntryRequest.builder()
                .employeeUserId(2L)
                .fields(Map.of())
                .build();

        assertThrows(IllegalArgumentException.class,
                () -> fileManagementService.createStructuredEntry(20L, request, 2L));
        verify(documentComplianceService, never()).recordStructuredEntrySaved(any(), any(), any());
    }

    @Test
    @DisplayName("isExtractFailurePlaceholder - keeps citation-like text starting with [")
    void isExtractFailurePlaceholder_keepsLegitimateBracketText() {
        assertFalse(FileManagementService.isExtractFailurePlaceholder(
                "[1] Patient was advised to continue metformin."));
        assertTrue(FileManagementService.isExtractFailurePlaceholder(
                "[Error extracting PDF content: boom]"));
        assertTrue(FileManagementService.isExtractFailurePlaceholder(
                "[Unable to extract text from: scan.png]"));
        assertTrue(FileManagementService.isExtractFailurePlaceholder("   "));
    }

    @Test
    @DisplayName("indexableDocumentText - prefers extracted body and merges description")
    void indexableDocumentText_mergesDescriptionAndExtracted() {
        final UserFile file = UserFile.builder()
                .description("Discharge summary")
                .extractedText("Continue current medications as prescribed.")
                .build();
        assertEquals(
                "Discharge summary\n\nContinue current medications as prescribed.",
                FileManagementService.indexableDocumentText(file));
    }

    @Test
    @DisplayName("uploadFile - empty local extract enqueues async Ask AI OCR")
    void uploadFile_emptyExtract_enqueuesAsyncOcr() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(2048L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("scan.pdf");
        when(multipartFile.getBytes()).thenReturn(new byte[]{1, 2, 3, 4});
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");
        when(documentProcessingService.extractTextContent(any()))
                .thenReturn("[Unable to extract text from: scan.pdf]");

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "Scan", 1L);

        assertNotNull(result);
        verify(askAiDocumentOcrService).enqueueAfterFailedExtract(eq(userFile));
    }

    @Test
    @DisplayName("uploadFile - local extract success does not enqueue OCR")
    void uploadFile_localExtractSucceeds_skipsOcrEnqueue() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(1024L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("report.pdf");
        when(multipartFile.getBytes()).thenReturn("pdf-bytes".getBytes());
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");
        when(documentProcessingService.extractTextContent(any()))
                .thenReturn("Native PDF text body");

        fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "desc", 1L);

        verify(askAiDocumentOcrService, never()).enqueueAfterFailedExtract(any());
    }

    @Test
    @DisplayName("uploadFile - extract exception still enqueues OCR when bytes readable")
    void uploadFile_extractThrows_enqueuesOcr() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(2048L);
        when(multipartFile.getContentType()).thenReturn("image/png");
        when(multipartFile.getOriginalFilename()).thenReturn("scan.png");
        when(multipartFile.getBytes()).thenReturn(new byte[]{1, 2, 3});
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("db://files/10");
        userFile.setContentType("image/png");
        userFile.setOriginalFilename("scan.png");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");
        when(documentProcessingService.extractTextContent(any()))
                .thenThrow(new RuntimeException("parser boom"));

        fileManagementService.uploadFile(multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "Scan", 1L);

        verify(askAiDocumentOcrService).enqueueAfterFailedExtract(eq(userFile));
    }

    @Test
    @DisplayName("uploadFile - extract getBytes failure still enqueues OCR after commit path")
    void uploadFile_extractAndBytesFail_stillSucceeds() throws Exception {
        when(multipartFile.isEmpty()).thenReturn(false);
        when(multipartFile.getSize()).thenReturn(2048L);
        when(multipartFile.getContentType()).thenReturn("application/pdf");
        when(multipartFile.getOriginalFilename()).thenReturn("scan.pdf");
        when(multipartFile.getBytes()).thenThrow(new java.io.IOException("read failed"));
        when(databaseStorageService.uploadFile(eq(multipartFile), eq(1L), eq("PATIENT"), eq("MEDICAL_RECORD")))
                .thenReturn("db://files/10");
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));
        when(databaseStorageService.getFileUrl(anyString())).thenReturn("http://localhost/files/10");

        final FileUploadResponse result = fileManagementService.uploadFile(
                multipartFile, 1L, "PATIENT", "MEDICAL_RECORD", "Scan", 1L);

        assertNotNull(result);
        // Enqueue is best-effort after extract failure; OCR worker reloads bytes from storage.
        verify(askAiDocumentOcrService).enqueueAfterFailedExtract(eq(userFile));
    }

    @Test
    @DisplayName("tryExtractAndPersistText - null guards are no-ops")
    void tryExtractAndPersistText_nullGuards() {
        ReflectionTestUtils.invokeMethod(
                fileManagementService, "tryExtractAndPersistText", null, multipartFile);
        ReflectionTestUtils.invokeMethod(
                fileManagementService, "tryExtractAndPersistText", userFile, null);
        verify(askAiDocumentOcrService, never()).enqueueAfterFailedExtract(any());
    }

    @Test
    @DisplayName("indexableDocumentText - extracted only and description only")
    void indexableDocumentText_singleFieldFallbacks() {
        final UserFile extractedOnly = UserFile.builder()
                .extractedText("Body only")
                .build();
        assertEquals("Body only", FileManagementService.indexableDocumentText(extractedOnly));

        final UserFile descriptionOnly = UserFile.builder()
                .description("Desc only")
                .build();
        assertEquals("Desc only", FileManagementService.indexableDocumentText(descriptionOnly));

        assertNull(FileManagementService.indexableDocumentText(UserFile.builder().build()));
    }
}


