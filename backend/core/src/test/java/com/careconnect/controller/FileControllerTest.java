package com.careconnect.controller;

import com.careconnect.dto.FileUploadResponse;
import com.careconnect.dto.UserFileDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.PatientService;
import com.careconnect.service.S3StorageService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class FileControllerTest {

    @Mock private S3StorageService s3StorageService;
    @Mock private FileManagementService fileManagementService;
    @Mock private UserRepository userRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private MessageRepository messageRepository;
    @Mock private CaregiverService caregiverService;
    @Mock private PatientService patientService;
    @Mock private Authentication authentication;
    @Mock private SecurityContext securityContext;

    @InjectMocks
    private FileController controller;

    private static final String USER_EMAIL = "user@example.com";
    private static final Long   USER_ID    = 1L;
    private static final Long   PATIENT_ID = 2L;
    private static final Long   FILE_ID    = 10L;

    @BeforeEach
    void setUp() throws Exception {
        lenient().when(securityContext.getAuthentication()).thenReturn(authentication);
        SecurityContextHolder.setContext(securityContext);
        lenient().when(authentication.getName()).thenReturn(USER_EMAIL);
    }

    @AfterEach
    void tearDown() throws Exception {
        SecurityContextHolder.clearContext();
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    private User makeUser(Role role) {
        final User u = new User();
        u.setId(USER_ID);
        u.setEmail(USER_EMAIL);
        u.setRole(role);
        return u;
    }

    private UserFileDTO makeFileDto(Long ownerId, Long patientId) {
        return UserFileDTO.builder()
                .id(FILE_ID)
                .ownerId(ownerId)
                .patientId(patientId)
                .originalFilename("test.pdf")
                .contentType("application/pdf")
                .build();
    }

    private MockMultipartFile makeFile() throws Exception {
        return new MockMultipartFile("file", "test.pdf", "application/pdf", "content".getBytes());
    }

    // ─── uploadFile ───────────────────────────────────────────────────────────

    @Test
    void uploadFile_success_noPatientId() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final FileUploadResponse resp = FileUploadResponse.builder().fileId(FILE_ID).filename("f.pdf").build();
        when(fileManagementService.uploadFile(any(), eq(USER_ID), eq("PATIENT"),
                eq("OTHER_DOCUMENT"), isNull(), isNull())).thenReturn(resp);

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsKey("data");
        assertThat(body.get("message")).isEqualTo("File uploaded successfully");
    }

    @Test
    void uploadFile_adminAccessToPatient_success() throws Exception {
        final User user = makeUser(Role.ADMIN);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final FileUploadResponse resp = FileUploadResponse.builder().fileId(FILE_ID).build();
        when(fileManagementService.uploadFile(any(), eq(USER_ID), eq("ADMIN"),
                eq("OTHER_DOCUMENT"), isNull(), eq(PATIENT_ID))).thenReturn(resp);

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void uploadFile_patientAccessingOwnId_success() throws Exception {
        final User user = makeUser(Role.PATIENT);
        user.setId(PATIENT_ID); // same id as patientId
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final FileUploadResponse resp = FileUploadResponse.builder().fileId(FILE_ID).build();
        when(fileManagementService.uploadFile(any(), eq(PATIENT_ID), eq("PATIENT"),
                eq("OTHER_DOCUMENT"), isNull(), eq(PATIENT_ID))).thenReturn(resp);

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void uploadFile_patientAccessingOtherPatient_forbidden() throws Exception {
        final User user = makeUser(Role.PATIENT); // USER_ID=1, patientId=2
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void uploadFile_caregiverHasAccess_success() throws Exception {
        final User user = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(new Patient()));
        when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
        final FileUploadResponse resp = FileUploadResponse.builder().fileId(FILE_ID).build();
        when(fileManagementService.uploadFile(any(), eq(USER_ID), eq("CAREGIVER"),
                eq("OTHER_DOCUMENT"), isNull(), eq(PATIENT_ID))).thenReturn(resp);

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void uploadFile_caregiverNoAccess_forbidden() throws Exception {
        final User user = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(new Patient()));
        when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void uploadFile_caregiverPatientNotFound_forbidden() throws Exception {
        final User user = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void uploadFile_familyMemberRole_forbidden() throws Exception {
        final User user = makeUser(Role.FAMILY_MEMBER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void uploadFile_illegalArgumentException_returns400() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.uploadFile(any(), any(), any(), any(), any(), any()))
                .thenThrow(new IllegalArgumentException("bad input"));

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void uploadFile_genericException_returns500() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.uploadFile(any(), any(), any(), any(), any(), any()))
                .thenThrow(new RuntimeException("unexpected"));

        final ResponseEntity<?> response = controller.uploadFile(makeFile(), "OTHER_DOCUMENT", null, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── downloadFile (new DB endpoint) ──────────────────────────────────────

    @Test
    void downloadFile_notFound() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.downloadFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void downloadFile_forbidden_differentOwner_noPatientId() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final UserFileDTO dto = makeFileDto(999L, null);
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.of(dto));

        final ResponseEntity<?> response = controller.downloadFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void downloadFile_success_ownerAccess() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final UserFileDTO dto = makeFileDto(USER_ID, null);
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.of(dto));
        when(fileManagementService.downloadFile(FILE_ID)).thenReturn("data".getBytes());

        final ResponseEntity<?> response = controller.downloadFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void downloadFile_success_adminAccess() throws Exception {
        final User admin = makeUser(Role.ADMIN);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
        final UserFileDTO dto = makeFileDto(999L, null);
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.of(dto));
        when(fileManagementService.downloadFile(FILE_ID)).thenReturn("bytes".getBytes());

        final ResponseEntity<?> response = controller.downloadFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void downloadFile_viaPatientAccess_caregiver() throws Exception {
        final User caregiver = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
        final UserFileDTO dto = makeFileDto(999L, PATIENT_ID);
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.of(dto));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(new Patient()));
        when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
        when(fileManagementService.downloadFile(FILE_ID)).thenReturn("bytes".getBytes());

        final ResponseEntity<?> response = controller.downloadFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void downloadFile_caregiverNoAccessToPatient_forbidden() throws Exception {
        final User caregiver = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
        final UserFileDTO dto = makeFileDto(999L, PATIENT_ID);
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.of(dto));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(new Patient()));
        when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

        final ResponseEntity<?> response = controller.downloadFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void downloadFile_exception_returns500() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.getFile(FILE_ID)).thenThrow(new RuntimeException("oops"));

        final ResponseEntity<?> response = controller.downloadFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── listMyFiles ──────────────────────────────────────────────────────────

    @Test
    void listMyFiles_noCategory_returns200() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.listUserFiles(USER_ID, "PATIENT", null)).thenReturn(List.of());

        final ResponseEntity<?> response = controller.listMyFiles(null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("message")).isEqualTo("Files retrieved successfully");
    }

    @Test
    void listMyFiles_withCategory_returns200() throws Exception {
        final User user = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.listUserFiles(USER_ID, "CAREGIVER", "documents")).thenReturn(List.of());

        final ResponseEntity<?> response = controller.listMyFiles("documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void listMyFiles_exception_returns500() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.listUserFiles(any(), any(), any()))
                .thenThrow(new RuntimeException("db error"));

        final ResponseEntity<?> response = controller.listMyFiles(null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── listPatientFiles ─────────────────────────────────────────────────────

    @Test
    void listPatientFiles_forbidden_caregiverNoAccess() throws Exception {
        final User user = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(new Patient()));
        when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

        final ResponseEntity<?> response = controller.listPatientFiles(PATIENT_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void listPatientFiles_caregiverNoPatientRecord_forbidden() throws Exception {
        final User user = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.listPatientFiles(PATIENT_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void listPatientFiles_patientRole_ownData_success() throws Exception {
        final User user = makeUser(Role.PATIENT);
        user.setId(PATIENT_ID); // same id → access granted
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.listFilesForPatient(PATIENT_ID, null)).thenReturn(List.of());

        final ResponseEntity<?> response = controller.listPatientFiles(PATIENT_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void listPatientFiles_caregiverRole_withCategory_success() throws Exception {
        final User user = makeUser(Role.CAREGIVER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(new Patient()));
        when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
        when(fileManagementService.listFilesForCaregiverPatient(PATIENT_ID, "documents"))
                .thenReturn(List.of());

        final ResponseEntity<?> response = controller.listPatientFiles(PATIENT_ID, "documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void listPatientFiles_adminRole_success() throws Exception {
        final User user = makeUser(Role.ADMIN);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.listFilesForCaregiverPatient(PATIENT_ID, null)).thenReturn(List.of());

        final ResponseEntity<?> response = controller.listPatientFiles(PATIENT_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void listPatientFiles_familyMemberRole_forbidden() throws Exception {
        final User user = makeUser(Role.FAMILY_MEMBER);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.listPatientFiles(PATIENT_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void listPatientFiles_exception_returns500() throws Exception {
        final User user = makeUser(Role.ADMIN);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.listFilesForCaregiverPatient(any(), any()))
                .thenThrow(new RuntimeException("fail"));

        final ResponseEntity<?> response = controller.listPatientFiles(PATIENT_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── deleteFile (new DB endpoint) ─────────────────────────────────────────

    @Test
    void deleteFile_new_notFound() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.deleteFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void deleteFile_new_forbidden_notOwner() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final UserFileDTO dto = makeFileDto(999L, null);
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.of(dto));

        final ResponseEntity<?> response = controller.deleteFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void deleteFile_new_success() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final UserFileDTO dto = makeFileDto(USER_ID, null);
        when(fileManagementService.getFile(FILE_ID)).thenReturn(Optional.of(dto));
        doNothing().when(fileManagementService).deleteFile(FILE_ID, USER_ID);

        final ResponseEntity<?> response = controller.deleteFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void deleteFile_new_exception_returns500() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.getFile(FILE_ID)).thenThrow(new RuntimeException("err"));

        final ResponseEntity<?> response = controller.deleteFile(FILE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── getProfileImage ──────────────────────────────────────────────────────

    @Test
    void getProfileImage_notFound() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.getUserProfileImage(USER_ID, "PATIENT")).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.getProfileImage();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void getProfileImage_found() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        final UserFileDTO dto = makeFileDto(USER_ID, null);
        when(fileManagementService.getUserProfileImage(USER_ID, "PATIENT")).thenReturn(Optional.of(dto));

        final ResponseEntity<?> response = controller.getProfileImage();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("data")).isSameAs(dto);
    }

    @Test
    void getProfileImage_exception_returns500() throws Exception {
        final User user = makeUser(Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(fileManagementService.getUserProfileImage(any(), any()))
                .thenThrow(new RuntimeException("err"));

        final ResponseEntity<?> response = controller.getProfileImage();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── uploadFileLegacy (S3 endpoint) ──────────────────────────────────────

    @Test
    void uploadFileLegacy_success() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        final MockMultipartFile file = new MockMultipartFile("file", "doc.pdf", "application/pdf", new byte[100]);
        when(s3StorageService.uploadFile(any(MultipartFile.class), eq(USER_ID), eq("PATIENT"), eq("documents")))
                .thenReturn("patient_1/documents/doc.pdf");
        when(s3StorageService.getFileUrl("patient_1/documents/doc.pdf"))
                .thenReturn("https://s3.example.com/patient_1/documents/doc.pdf");

        final ResponseEntity<?> response = controller.uploadFileLegacy(USER_ID, file, "documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("message")).isEqualTo("File uploaded successfully");
    }

    @Test
    void uploadFileLegacy_emptyFile_returns400() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        final MockMultipartFile emptyFile = new MockMultipartFile("file", "empty.pdf", "application/pdf", new byte[0]);

        final ResponseEntity<?> response = controller.uploadFileLegacy(USER_ID, emptyFile, "documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void uploadFileLegacy_fileTooLarge_returns400() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        final MockMultipartFile bigFile = new MockMultipartFile("file", "big.pdf", "application/pdf",
                new byte[11 * 1024 * 1024]);

        final ResponseEntity<?> response = controller.uploadFileLegacy(USER_ID, bigFile, "documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void uploadFileLegacy_userNotFound_returns500() throws Exception {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.uploadFileLegacy(USER_ID, makeFile(), "documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    @Test
    void uploadFileLegacy_s3Throws_returns500() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(s3StorageService.uploadFile(any(), any(), any(), any()))
                .thenThrow(new RuntimeException("S3 down"));

        final ResponseEntity<?> response = controller.uploadFileLegacy(USER_ID, makeFile(), "documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── downloadFile (S3 endpoint) ───────────────────────────────────────────

    @Test
    void downloadFileLegacy_success() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(s3StorageService.download("patient_1/documents/file.pdf")).thenReturn("data".getBytes());

        final ResponseEntity<byte[]> response = controller.downloadFile(USER_ID, "/patient_1/documents/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void downloadFileLegacy_forbidden_wrongPrefix() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        final ResponseEntity<byte[]> response = controller.downloadFile(USER_ID, "/other_99/docs/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void downloadFileLegacy_userNotFound_returns404() throws Exception {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<byte[]> response = controller.downloadFile(USER_ID, "/patient_1/documents/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void downloadFileLegacy_s3Throws_returns404() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(s3StorageService.download(any())).thenThrow(new RuntimeException("S3 err"));

        final ResponseEntity<byte[]> response = controller.downloadFile(USER_ID, "/patient_1/documents/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    // ─── deleteFile legacy (S3 endpoint) ─────────────────────────────────────

    @Test
    void deleteFileLegacy_success() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        doNothing().when(s3StorageService).deleteFile("patient_1/documents/file.pdf");

        final ResponseEntity<?> response = controller.deleteFile(USER_ID, "/patient_1/documents/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void deleteFileLegacy_forbidden_wrongPrefix() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.deleteFile(USER_ID, "/other_99/docs/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void deleteFileLegacy_userNotFound_returns500() throws Exception {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.deleteFile(USER_ID, "/patient_1/documents/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    @Test
    void deleteFileLegacy_s3Throws_returns500() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        doThrow(new RuntimeException("S3 err")).when(s3StorageService).deleteFile(any());

        final ResponseEntity<?> response = controller.deleteFile(USER_ID, "/patient_1/documents/file.pdf");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── listUserFiles (S3 endpoint) ──────────────────────────────────────────

    @Test
    void listUserFilesLegacy_noCategory() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        // This endpoint serves the S3 listing only when S3 is enabled; otherwise
        // it falls back to DB listing. Exercise the S3 path here.
        ReflectionTestUtils.setField(controller, "useS3ForLegacyEndpoints", true);
        when(s3StorageService.listUserFilesDto(USER_ID, "PATIENT")).thenReturn(List.of());

        final ResponseEntity<?> response = controller.listUserFiles(USER_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("category")).isEqualTo("all");
    }

    @Test
    void listUserFilesLegacy_withCategory_matchingFile() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        final UserFileDTO dto = UserFileDTO.builder().s3FullKey("patient_1/documents/doc.pdf").build();
        ReflectionTestUtils.setField(controller, "useS3ForLegacyEndpoints", true);
        when(s3StorageService.listUserFilesDto(USER_ID, "PATIENT")).thenReturn(List.of(dto));

        final ResponseEntity<?> response = controller.listUserFiles(USER_ID, "documents");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        @SuppressWarnings("unchecked")
        final List<UserFileDTO> files = (List<UserFileDTO>) body.get("files");
        assertThat(files).hasSize(1);
    }

    @Test
    void listUserFilesLegacy_withCategory_noMatch() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        final UserFileDTO dto = UserFileDTO.builder().s3FullKey("patient_1/documents/doc.pdf").build();
        ReflectionTestUtils.setField(controller, "useS3ForLegacyEndpoints", true);
        when(s3StorageService.listUserFilesDto(USER_ID, "PATIENT")).thenReturn(List.of(dto));

        final ResponseEntity<?> response = controller.listUserFiles(USER_ID, "prescriptions");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        @SuppressWarnings("unchecked")
        final List<UserFileDTO> files = (List<UserFileDTO>) body.get("files");
        assertThat(files).isEmpty();
    }

    @Test
    void listUserFilesLegacy_userNotFound_returns500() throws Exception {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.listUserFiles(USER_ID, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    // ─── getValidCategories ───────────────────────────────────────────────────

    @Test
    void getValidCategories_patient() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.PATIENT);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.getValidCategories(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        @SuppressWarnings("unchecked")
        final List<String> categories = (List<String>) body.get("categories");
        assertThat(categories).contains("profile", "documents", "medical-records");
    }

    @Test
    void getValidCategories_caregiver() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.CAREGIVER);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.getValidCategories(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        @SuppressWarnings("unchecked")
        final List<String> categories = (List<String>) body.get("categories");
        assertThat(categories).contains("certifications");
    }

    @Test
    void getValidCategories_familyMember() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.FAMILY_MEMBER);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.getValidCategories(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        @SuppressWarnings("unchecked")
        final List<String> categories = (List<String>) body.get("categories");
        assertThat(categories).contains("authorization");
    }

    @Test
    void getValidCategories_admin_defaultList() throws Exception {
        final User user = new User();
        user.setId(USER_ID);
        user.setRole(Role.ADMIN);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.getValidCategories(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        @SuppressWarnings("unchecked")
        final List<String> categories = (List<String>) body.get("categories");
        assertThat(categories).containsExactly("documents");
    }

    @Test
    void getValidCategories_userNotFound_returns500() throws Exception {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.getValidCategories(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }
}
