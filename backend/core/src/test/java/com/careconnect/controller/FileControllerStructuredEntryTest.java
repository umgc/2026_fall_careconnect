package com.careconnect.controller;

import com.careconnect.dto.StructuredDocumentEntryDTO;
import com.careconnect.dto.StructuredEntryRequest;
import com.careconnect.dto.UserFileDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
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
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-layer tests for the structured form-entry endpoints on
 * {@link FileController} (Home Care Document Digitization).
 *
 * <p>Same slice setup as the project's other controller tests: only the MVC
 * layer loads, the service is mocked, and the {@link SecurityContextHolder} is
 * configured per test to select the current principal.</p>
 */
@WebMvcTest(FileController.class)
@AutoConfigureMockMvc(addFilters = false)
class FileControllerStructuredEntryTest {

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
    private User caregiverUser;

    @BeforeEach
    void setup() {
        patientUser = new User();
        patientUser.setId(1L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);

        caregiverUser = new User();
        caregiverUser.setId(3L);
        caregiverUser.setEmail("caregiver@test.com");
        caregiverUser.setRole(Role.CAREGIVER);
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

    /** A file owned by the patient user (id 1). */
    private UserFileDTO ownFile() {
        return UserFileDTO.builder()
                .id(20L).ownerId(1L).ownerType("PATIENT").patientId(1L)
                .fileCategory("EMERGENCY_CONTACT")
                .originalFilename("emergency.pdf").contentType("application/pdf")
                .uploadedAt(LocalDateTime.now())
                .build();
    }

    private StructuredDocumentEntryDTO entryDto() {
        return StructuredDocumentEntryDTO.builder()
                .id(5L).fileId(20L).documentType("EMERGENCY_CONTACT")
                .patientId(1L)
                .fields(Map.of("contactName", "John Doe",
                        "relationship", "Son", "phone", "555-0100"))
                .originalFilename("emergency.pdf")
                .build();
    }

    private static final String VALID_BODY = """
            {"documentType":"EMERGENCY_CONTACT","patientId":1,
             "fields":{"contactName":"John Doe","relationship":"Son","phone":"555-0100"}}
            """;

    // ───────────────────────── Create ─────────────────────────

    @Test
    @DisplayName("Create: valid entry is persisted linked to the file and attributed to the caller")
    void create_valid_persistedAgainstFile() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(ownFile()));
        when(fileManagementService.createStructuredEntry(eq(20L), any(), eq(1L)))
                .thenReturn(entryDto());

        mockMvc.perform(post("/v1/api/files/20/structured-entry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(VALID_BODY))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.fileId").value(20))
                .andExpect(jsonPath("$.data.fields.contactName").value("John Doe"))
                .andExpect(jsonPath("$.data.originalFilename").value("emergency.pdf"));

        ArgumentCaptor<StructuredEntryRequest> captor =
                ArgumentCaptor.forClass(StructuredEntryRequest.class);
        verify(fileManagementService).createStructuredEntry(eq(20L), captor.capture(), eq(1L));
        assertThat(captor.getValue().getPatientId()).isEqualTo(1L);
        assertThat(captor.getValue().getFields()).containsEntry("phone", "555-0100");
    }

    @Test
    @DisplayName("Create: rejects a save without patient or employee context (400)")
    void create_missingContext_rejectedWith400() throws Exception {
        asUser(patientUser);
        // File with no linked patient, request with no context: the service's
        // context rule fires and the controller must surface it as a 400.
        UserFileDTO orphanContextFile = UserFileDTO.builder()
                .id(20L).ownerId(1L).ownerType("PATIENT").patientId(null)
                .fileCategory("EMERGENCY_CONTACT").originalFilename("emergency.pdf")
                .uploadedAt(LocalDateTime.now()).build();
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(orphanContextFile));
        when(fileManagementService.createStructuredEntry(eq(20L), any(), eq(1L)))
                .thenThrow(new IllegalArgumentException(
                        "A patient or employee context is required before saving a structured entry"));

        mockMvc.perform(post("/v1/api/files/20/structured-entry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fields\":{\"contactName\":\"John Doe\"}}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error",
                        containsString("patient or employee context is required")));
    }

    @Test
    @DisplayName("Create: rejects incomplete required fields (400 with field names)")
    void create_missingRequiredFields_rejectedWith400() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(ownFile()));
        when(fileManagementService.createStructuredEntry(eq(20L), any(), eq(1L)))
                .thenThrow(new IllegalArgumentException(
                        "Missing required fields for EMERGENCY_CONTACT: phone, relationship"));

        mockMvc.perform(post("/v1/api/files/20/structured-entry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"patientId\":1,\"fields\":{\"contactName\":\"John Doe\"}}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error", containsString("Missing required fields")))
                .andExpect(jsonPath("$.error", containsString("phone")));
    }

    @Test
    @DisplayName("Create: unknown file returns 404 (no orphan structured records)")
    void create_unknownFile_returns404() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getFile(99L)).thenReturn(Optional.empty());

        mockMvc.perform(post("/v1/api/files/99/structured-entry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(VALID_BODY))
                .andExpect(status().isNotFound());

        verify(fileManagementService, never()).createStructuredEntry(anyLong(), any(), anyLong());
    }

    @Test
    @DisplayName("Create: patient cannot save an entry against another patient's context (403)")
    void create_otherPatientContext_forbidden() throws Exception {
        asUser(patientUser); // id 1
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(ownFile()));
        when(patientRepository.findById(2L)).thenReturn(Optional.of(new Patient()));

        mockMvc.perform(post("/v1/api/files/20/structured-entry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"patientId\":2,\"fields\":{\"contactName\":\"X\"}}"))
                .andExpect(status().isForbidden());

        verify(fileManagementService, never()).createStructuredEntry(anyLong(), any(), anyLong());
    }

    @Test
    @DisplayName("Create: non-admin cannot save an entry for another employee (403)")
    void create_otherEmployeeContext_forbidden() throws Exception {
        asUser(caregiverUser); // id 3
        UserFileDTO caregiverFile = UserFileDTO.builder()
                .id(20L).ownerId(3L).ownerType("CAREGIVER").patientId(null)
                .fileCategory("CERTIFICATION").originalFilename("cpr.pdf")
                .uploadedAt(LocalDateTime.now()).build();
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(caregiverFile));

        mockMvc.perform(post("/v1/api/files/20/structured-entry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"employeeUserId\":8,\"fields\":{\"certificationName\":\"CPR\"}}"))
                .andExpect(status().isForbidden());

        verify(fileManagementService, never()).createStructuredEntry(anyLong(), any(), anyLong());
    }

    // ───────────────────────── Read ─────────────────────────

    @Test
    @DisplayName("Get: returns the structured entry with the original file still linked")
    void get_returnsEntryWithLinkedFile() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(ownFile()));
        when(fileManagementService.getStructuredEntryForFile(20L))
                .thenReturn(Optional.of(entryDto()));

        mockMvc.perform(get("/v1/api/files/20/structured-entry"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.fileId").value(20))
                .andExpect(jsonPath("$.data.originalFilename").value("emergency.pdf"));
    }

    @Test
    @DisplayName("Get: 404 when the file has no structured entry yet")
    void get_noEntry_returns404() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(ownFile()));
        when(fileManagementService.getStructuredEntryForFile(20L)).thenReturn(Optional.empty());

        mockMvc.perform(get("/v1/api/files/20/structured-entry"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error", containsString("No structured entry")));
    }

    @Test
    @DisplayName("Get: a user cannot read a structured entry for a file outside their context (403)")
    void get_foreignFile_forbidden() throws Exception {
        asUser(patientUser); // id 1
        UserFileDTO foreignFile = UserFileDTO.builder()
                .id(21L).ownerId(2L).ownerType("PATIENT").patientId(null)
                .fileCategory("EMERGENCY_CONTACT").originalFilename("x.pdf")
                .uploadedAt(LocalDateTime.now()).build();
        when(fileManagementService.getFile(21L)).thenReturn(Optional.of(foreignFile));
        when(messageRepository.existsAttachmentInUserConversation(21L, 1L)).thenReturn(false);

        mockMvc.perform(get("/v1/api/files/21/structured-entry"))
                .andExpect(status().isForbidden());

        verify(fileManagementService, never()).getStructuredEntryForFile(anyLong());
    }

    // ───────────────────────── Update ─────────────────────────

    @Test
    @DisplayName("Update: editing an entry calls update, never create, and keeps the file link")
    void update_callsUpdateNotCreate() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getStructuredEntry(5L)).thenReturn(Optional.of(entryDto()));
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(ownFile()));
        when(fileManagementService.updateStructuredEntry(eq(5L), any())).thenReturn(entryDto());

        mockMvc.perform(put("/v1/api/files/structured-entries/5")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(VALID_BODY))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.fileId").value(20));

        verify(fileManagementService).updateStructuredEntry(eq(5L), any());
        verify(fileManagementService, never()).createStructuredEntry(anyLong(), any(), anyLong());
    }

    @Test
    @DisplayName("Update: unknown entry returns 404")
    void update_unknownEntry_returns404() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getStructuredEntry(99L)).thenReturn(Optional.empty());

        mockMvc.perform(put("/v1/api/files/structured-entries/99")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(VALID_BODY))
                .andExpect(status().isNotFound());

        verify(fileManagementService, never()).updateStructuredEntry(anyLong(), any());
    }

    @Test
    @DisplayName("Update: incomplete required fields are rejected (400)")
    void update_missingRequiredFields_rejectedWith400() throws Exception {
        asUser(patientUser);
        when(fileManagementService.getStructuredEntry(5L)).thenReturn(Optional.of(entryDto()));
        when(fileManagementService.getFile(20L)).thenReturn(Optional.of(ownFile()));
        when(fileManagementService.updateStructuredEntry(eq(5L), any()))
                .thenThrow(new IllegalArgumentException(
                        "Missing required fields for EMERGENCY_CONTACT: contactName"));

        mockMvc.perform(put("/v1/api/files/structured-entries/5")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"patientId\":1,\"fields\":{}}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error", containsString("contactName")));
    }

    // ───────────────────────── Patient listing ─────────────────────────

    @Test
    @DisplayName("Patient listing: entries are returned under the correct patient context")
    void list_ownPatientContext_ok() throws Exception {
        asUser(patientUser); // id 1
        when(fileManagementService.listStructuredEntriesForPatient(1L))
                .thenReturn(java.util.List.of(entryDto()));

        mockMvc.perform(get("/v1/api/files/structured-entries/patient/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].patientId").value(1))
                .andExpect(jsonPath("$.data[0].fileId").value(20));
    }

    @Test
    @DisplayName("Patient listing: a patient cannot list another patient's entries (403)")
    void list_otherPatient_forbidden() throws Exception {
        asUser(patientUser); // id 1
        when(patientRepository.findById(2L)).thenReturn(Optional.of(new Patient()));

        mockMvc.perform(get("/v1/api/files/structured-entries/patient/2"))
                .andExpect(status().isForbidden());

        verify(fileManagementService, never()).listStructuredEntriesForPatient(anyLong());
    }
}
