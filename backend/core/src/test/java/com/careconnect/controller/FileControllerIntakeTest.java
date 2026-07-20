package com.careconnect.controller;

import com.careconnect.dto.FileUploadResponse;
import com.careconnect.dto.UserFileDTO;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.PatientService;
import com.careconnect.service.S3StorageService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-layer tests for {@link FileController}, focused on the Home-Care Document
 * Intake Workflow (typed category alignment).
 *
 * <p>Uses {@code @WebMvcTest} + {@code @AutoConfigureMockMvc(addFilters = false)}
 * so only the MVC slice loads (no DB, no security filter chain, no AOP permission
 * aspect). The {@link SecurityContextHolder} is configured directly per test to
 * choose the current principal, mirroring the project's existing controller tests.
 */
@WebMvcTest(FileController.class)
@AutoConfigureMockMvc(addFilters = false)
class FileControllerIntakeTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean private FileManagementService fileManagementService;
    @MockitoBean private S3StorageService s3StorageService;
    @MockitoBean private UserRepository userRepository;
    @MockitoBean private PatientRepository patientRepository;
    @MockitoBean private MessageRepository messageRepository;
    @MockitoBean private CaregiverService caregiverService;
    @MockitoBean private PatientService patientService;
    @MockitoBean private AuthorizationService authorizationService;
    @MockitoBean private SecurityUtil securityUtil;

    private User patientUser;
    private User adminUser;

    @BeforeEach
    void setup() {
        patientUser = new User();
        patientUser.setId(1L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);

        adminUser = new User();
        adminUser.setId(99L);
        adminUser.setEmail("admin@test.com");
        adminUser.setRole(Role.ADMIN);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private void asUser(User user) {
        Authentication auth = Mockito.mock(Authentication.class);
        when(auth.getName()).thenReturn(user.getEmail());
        SecurityContext ctx = Mockito.mock(SecurityContext.class);
        when(ctx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(ctx);
        when(userRepository.findByEmail(user.getEmail())).thenReturn(Optional.of(user));
    }

    private MockMultipartFile sampleFile() {
        return new MockMultipartFile("file", "form.pdf", "application/pdf", "data".getBytes());
    }

    private FileUploadResponse uploadResponse(String category) {
        return FileUploadResponse.builder()
                .fileId(10L).filename("f").originalFilename("form.pdf")
                .category(category).message("File uploaded successfully").build();
    }

    // ───────────────────────── Valid category upload ─────────────────────────

    @Test
    @DisplayName("Valid category upload: approved category is accepted (200) and passed to the service")
    void validCategoryUpload_accepted() throws Exception {
        asUser(patientUser);
        when(fileManagementService.uploadFile(any(), anyLong(), anyString(), anyString(), any(), any()))
                .thenReturn(uploadResponse("MEDICAL_RECORD"));

        mockMvc.perform(multipart("/v1/api/files/upload")
                        .file(sampleFile())
                        .param("category", "MEDICAL_REPORT")) // frontend alias
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.category").value("MEDICAL_RECORD"));
    }

    // ───────────────────────── Invalid category rejection ────────────────────

    @Test
    @DisplayName("Invalid category rejection: unknown category returns 400 with a clear message")
    void invalidCategory_rejectedWith400() throws Exception {
        asUser(patientUser);

        mockMvc.perform(multipart("/v1/api/files/upload")
                        .file(sampleFile())
                        .param("category", "NOT_A_REAL_CATEGORY"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error", containsString("Invalid file category")))
                .andExpect(jsonPath("$.error", containsString("NOT_A_REAL_CATEGORY")));

        verify(fileManagementService, never())
                .uploadFile(any(), anyLong(), anyString(), anyString(), any(), any());
    }

    // ───────────────────────── Owner context ─────────────────────────────────

    @Test
    @DisplayName("Owner context: upload is attributed to the authenticated user and role")
    void ownerContext_passedToService() throws Exception {
        asUser(patientUser);
        when(fileManagementService.uploadFile(any(), anyLong(), anyString(), anyString(), any(), any()))
                .thenReturn(uploadResponse("OTHER_DOCUMENT"));

        mockMvc.perform(multipart("/v1/api/files/upload").file(sampleFile()))
                .andExpect(status().isOk());

        ArgumentCaptor<Long> ownerId = ArgumentCaptor.forClass(Long.class);
        ArgumentCaptor<String> ownerType = ArgumentCaptor.forClass(String.class);
        verify(fileManagementService).uploadFile(any(), ownerId.capture(), ownerType.capture(),
                anyString(), any(), any());
        org.assertj.core.api.Assertions.assertThat(ownerId.getValue()).isEqualTo(1L);
        org.assertj.core.api.Assertions.assertThat(ownerType.getValue()).isEqualTo("PATIENT");
    }

    // ───────────────────────── Patient context ───────────────────────────────

    @Test
    @DisplayName("Patient context: a patient may attach a file to their own patient record")
    void patientContext_selfAllowed() throws Exception {
        asUser(patientUser); // patient user id 1
        when(fileManagementService.uploadFile(any(), anyLong(), anyString(), anyString(), any(), eq(1L)))
                .thenReturn(uploadResponse("MEDICAL_RECORD"));

        mockMvc.perform(multipart("/v1/api/files/upload")
                        .file(sampleFile())
                        .param("category", "MEDICAL_RECORD")
                        .param("patientId", "1"))
                .andExpect(status().isOk());

        verify(fileManagementService).uploadFile(any(), eq(1L), eq("PATIENT"),
                eq("MEDICAL_RECORD"), any(), eq(1L));
    }

    @Test
    @DisplayName("Patient context: a patient cannot attach a file to a different patient (403)")
    void patientContext_otherPatientForbidden() throws Exception {
        asUser(patientUser); // id 1
        when(patientRepository.findById(2L)).thenReturn(Optional.of(new Patient()));

        mockMvc.perform(multipart("/v1/api/files/upload")
                        .file(sampleFile())
                        .param("category", "MEDICAL_RECORD")
                        .param("patientId", "2"))
                .andExpect(status().isForbidden());

        verify(fileManagementService, never())
                .uploadFile(any(), anyLong(), anyString(), anyString(), any(), any());
    }

    // ───────────────────────── Care-circle context (intake) ──────────────────

    @Test
    @DisplayName("Care-circle context: intake links the document to the care recipient (careCircleId)")
    void careCircleContext_intakeLinksToRecipient() throws Exception {
        asUser(adminUser); // admin passes the patient/care-circle access check
        when(fileManagementService.uploadFile(any(), anyLong(), anyString(), anyString(), any(), eq(5L)))
                .thenReturn(uploadResponse("ONBOARDING_FORM"));

        mockMvc.perform(multipart("/v1/api/files/intake")
                        .file(sampleFile())
                        .param("documentType", "ONBOARDING_FORM")
                        .param("careCircleId", "5"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.category").value("ONBOARDING_FORM"));

        // Care recipient (care circle anchor) propagated as the patient link.
        verify(fileManagementService).uploadFile(any(), eq(99L), eq("ADMIN"),
                eq("ONBOARDING_FORM"), any(), eq(5L));
    }

    @Test
    @DisplayName("Intake rejects a valid category that is not an intake document type (400)")
    void intake_nonIntakeType_rejected() throws Exception {
        asUser(adminUser);

        mockMvc.perform(multipart("/v1/api/files/intake")
                        .file(sampleFile())
                        .param("documentType", "MEDICAL_RECORD"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error", containsString("not a valid intake document type")));
    }

    // ───────────────────────── Null / missing category ───────────────────────

    @Test
    @DisplayName("Null/missing document type: intake upload without a type returns 400")
    void missingDocumentType_rejected() throws Exception {
        asUser(adminUser);

        mockMvc.perform(multipart("/v1/api/files/intake").file(sampleFile()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error", containsString("document type is required")));

        verify(fileManagementService, never())
                .uploadFile(any(), anyLong(), anyString(), anyString(), any(), any());
    }

    // ───────────────────────── Authorization ─────────────────────────────────

    @Test
    @DisplayName("Authorization: a user cannot download a file outside their permitted context (403)")
    void authorization_downloadOtherUsersFile_forbidden() throws Exception {
        asUser(patientUser); // id 1
        UserFileDTO otherUsersFile = UserFileDTO.builder()
                .id(77L).ownerId(2L).patientId(null)
                .contentType("application/pdf").originalFilename("secret.pdf")
                .uploadedAt(LocalDateTime.now()).build();
        when(fileManagementService.getFile(77L)).thenReturn(Optional.of(otherUsersFile));
        when(messageRepository.existsAttachmentInUserConversation(77L, 1L)).thenReturn(false);

        mockMvc.perform(get("/v1/api/files/77/download"))
                .andExpect(status().isForbidden());

        verify(fileManagementService, never()).downloadFile(anyLong());
    }

    // ───────────────────────── Role-based access ─────────────────────────────

    @Test
    @DisplayName("Role-based access: admin may list any patient's intake documents (200)")
    void roleBased_adminListsAnyPatient() throws Exception {
        asUser(adminUser);
        when(fileManagementService.listEmploymentDocumentsForPatient(2L)).thenReturn(List.of());

        mockMvc.perform(get("/v1/api/files/intake/patient/2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message", containsString("retrieved")));
    }

    @Test
    @DisplayName("Role-based access: a patient cannot list another patient's intake documents (403)")
    void roleBased_patientCannotListOtherPatient() throws Exception {
        asUser(patientUser); // id 1
        when(patientRepository.findById(2L)).thenReturn(Optional.of(new Patient()));

        mockMvc.perform(get("/v1/api/files/intake/patient/2"))
                .andExpect(status().isForbidden());

        verify(fileManagementService, never()).listEmploymentDocumentsForPatient(anyLong());
    }
}
