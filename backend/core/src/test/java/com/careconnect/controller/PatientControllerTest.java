package com.careconnect.controller;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.model.Caregiver;
import com.careconnect.model.Medication.MedicationType;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.util.SecurityUtil;
import com.careconnect.service.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(PatientController.class)
@DisplayName("PatientController Tests")
class PatientControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private PatientService patientService;
    @MockitoBean
    private FamilyMemberService familyMemberService;
    @MockitoBean
    private CaregiverPatientLinkService caregiverPatientLinkService;
    @MockitoBean
    private UserRepository userRepository;
    @MockitoBean
    private MoodPainLogService moodPainLogService;
    @MockitoBean
    private MedicationService medicationService;
    @MockitoBean
    private PatientRiskService patientRiskService;
    @MockitoBean
    private SecurityUtil securityUtil;
    @MockitoBean
    private AuthorizationService authorizationService;

    private ObjectMapper objectMapper;

    // ─── Shared fixtures ────────────────────────────────────────────────────────

    private User patientUser;
    private User caregiverUser;
    private User familyUser;
    private User adminUser;
    private Patient patient;

    @BeforeEach
    void setUp() throws Exception {
        objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

        patientUser = buildUser(1L, "patient@test.com", Role.PATIENT);
        caregiverUser = buildUser(2L, "caregiver@test.com", Role.CAREGIVER);
        familyUser = buildUser(3L, "family@test.com", Role.FAMILY_MEMBER);
        adminUser = buildUser(4L, "admin@test.com", Role.ADMIN);

        patient = new Patient();
        patient.setId(10L);
        patient.setUser(patientUser);

        // Stub securityUtil.resolveCurrentUser() so that any controller-level
        // or filter-level calls do not NPE. Default to patientUser.
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
    }

    // ─── Helpers ────────────────────────────────────────────────────────────────

    private User buildUser(Long id, String email, Role role) {
        final User u = new User();
        u.setId(id);
        u.setEmail(email);
        u.setRole(role);
        return u;
    }

    private void mockCurrentUser(User user) {
        when(userRepository.findByEmail(user.getEmail())).thenReturn(Optional.of(user));
    }

    private MoodPainLogResponse sampleLog() throws Exception {
        final MoodPainLogResponse temp = new MoodPainLogResponse();
        temp.setId(1L);
        temp.setMoodValue(7);
        temp.setPainValue(3);
        temp.setNote("Feelink okay");
        temp.setTimestamp(LocalDateTime.now());
        return temp;
    }

    private MedicationDTO sampleMedication() throws Exception {
        final MedicationDTO temp = MedicationDTO.builder()
                .id(1L)
                .patientId(10L)
                .medicationName("Aspirin")
                .dosage("100mg")
                .frequency("Daily")
                .route("Oral")
                .medicationType(MedicationType.OVER_THE_COUNTER)
                .prescribedBy("Dr. Smith")
                .prescribedDate("2022-01-01")
                .startDate("2022-01-02")
                .endDate("2022-01-31")
                .notes("Take with food")
                .isActive(true)
                .build();
        return temp;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  GET /v1/api/patients/me
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /me")
    class GetMyProfile {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns profile for authenticated patient")
        void returnsProfile_whenPatient() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientByUserId(1L)).thenReturn(patient);

            mockMvc.perform(get("/v1/api/patients/me"))
                    .andExpect(status().isOk());

            verify(patientService).getPatientByUserId(1L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 403 when called by CAREGIVER")
        void returns403_whenCaregiver() throws Exception {
            mockCurrentUser(caregiverUser);

            mockMvc.perform(get("/v1/api/patients/me"))
                    .andExpect(status().isForbidden());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Returns 403 when called by FAMILY_MEMBER")
        void returns403_whenFamilyMember() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(get("/v1/api/patients/me"))
                    .andExpect(status().isForbidden());
        }
    }

    @Nested
    @DisplayName("getCurrentUser() — via GET /me")
    class GetCurrentUser {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns user when email exists in repository")
        void returnsUser_whenEmailFound() throws Exception {
            when(userRepository.findByEmail("patient@test.com"))
                    .thenReturn(Optional.of(patientUser));
            when(patientService.getPatientByUserId(patientUser.getId()))
                    .thenReturn(patient);

            mockMvc.perform(get("/v1/api/patients/me"))
                    .andExpect(status().isOk());

            verify(userRepository).findByEmail("patient@test.com");
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Throws UNAUTHORIZED when email is not found in repository")
        void throwsUnauthorized_whenEmailNotFound() throws Exception {
            when(userRepository.findByEmail("patient@test.com"))
                    .thenReturn(Optional.empty());

            mockMvc.perform(get("/v1/api/patients/me"))
                    .andExpect(status().isUnauthorized());

            verify(userRepository).findByEmail("patient@test.com");
            verifyNoInteractions(patientService);
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  GET /v1/api/patients/{patientId}
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /{patientId}")
    class GetPatient {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can access their own record")
        void patientAccessesOwnRecord() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);

            mockMvc.perform(get("/v1/api/patients/10"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient cannot access another patient's record")
        void patientDeniedOtherRecord() throws Exception {
            mockCurrentUser(patientUser);

            final Patient otherPatient = new Patient();
            otherPatient.setId(99L);
            final User otherUser = buildUser(99L, "other@test.com", Role.PATIENT);
            otherPatient.setUser(otherUser);

            when(patientService.getPatientById(99L)).thenReturn(otherPatient);

            mockMvc.perform(get("/v1/api/patients/99"))
                    .andExpect(status().isForbidden());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver with active link can access patient")
        void caregiverWithLinkAccesses() throws Exception {
            mockCurrentUser(caregiverUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);

            mockMvc.perform(get("/v1/api/patients/10"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver without active link is denied")
        void caregiverWithoutLinkDenied() throws Exception {
            mockCurrentUser(caregiverUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(false);

            mockMvc.perform(get("/v1/api/patients/10"))
                    .andExpect(status().isForbidden());
        }

        @Test
        @WithMockUser(username = "admin@test.com")
        @DisplayName("Admin can access any patient")
        void adminAccessesAnyPatient() throws Exception {
            mockCurrentUser(adminUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);

            mockMvc.perform(get("/v1/api/patients/10"))
                    .andExpect(status().isOk());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  PUT /v1/api/patients/{patientId}
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("PUT /{patientId}")
    class UpdatePatient {

        // Minimal JSON body for a Patient update request.
        // Using a hand-crafted string avoids serialisation round-trip issues
        // caused by read-only computed properties on the User model (e.g.
        // permissions, isAdmin, isFamilyMember) that have no matching setter,
        // which would trigger HttpMessageNotReadableException.
        private static final String PATIENT_JSON = "{\"id\":10}";

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can update their own record")
        void patientCanUpdate() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(patientService.updatePatient(eq(10L), any(Patient.class))).thenReturn(patient);

            mockMvc.perform(put("/v1/api/patients/10")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(PATIENT_JSON))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot update — read-only")
        void familyMemberCannotUpdate() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(put("/v1/api/patients/10")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(PATIENT_JSON))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  GET /v1/api/patients/{patientId}/caregivers
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /{patientId}/caregivers")
    class GetCaregivers {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns list of caregivers for own patient")
        void returnsCaregivers() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(patientService.getCaregiversByPatient(10L)).thenReturn(List.of(new Caregiver()));

            mockMvc.perform(get("/v1/api/patients/10/caregivers"))
                    .andExpect(status().isOk());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  GET /v1/api/patients/{patientId}/provider
    // ════════════════════════════════════════════════════════════════════════════
    @Nested
    @DisplayName("GET /{patientId}/provider")
    class GetPrimaryCareProvider {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns primary care provider for a valid patient")
        void returnsPrimaryProvider() throws Exception {
            mockCurrentUser(patientUser);

            final Map<String, Object> providerData = Map.of(
                    "name", "Dr. Jane Smith",
                    "specialty", "General Practice",
                    "phone", "555-9876"
            );
            when(patientService.getPrimaryProvider(10L)).thenReturn(providerData);

            mockMvc.perform(get("/v1/api/patients/10/provider"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.name").value("Dr. Jane Smith"))
                    .andExpect(jsonPath("$.specialty").value("General Practice"))
                    .andExpect(jsonPath("$.phone").value("555-9876"));

            verify(patientService).getPrimaryProvider(10L);
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns empty map when no provider is assigned")
        void returnsEmptyMap_whenNoProvider() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPrimaryProvider(10L)).thenReturn(Map.of());

            mockMvc.perform(get("/v1/api/patients/10/provider"))
                    .andExpect(status().isOk())
                    .andExpect(content().json("{}"));
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns 404 when patient does not exist")
        void returns404_whenPatientNotFound() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPrimaryProvider(99L))
                    .thenThrow(new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

            mockMvc.perform(get("/v1/api/patients/99/provider"))
                    .andExpect(status().isNotFound());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  GET /v1/api/patients/{patientId}/family-members
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /{patientId}/family-members")
    class GetFamilyMembers {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns family members for own patient")
        void returnsFamilyMembers() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(familyMemberService.getFamilyMembersByPatientId(10L)).thenReturn(List.of());

            mockMvc.perform(get("/v1/api/patients/10/family-members"))
                    .andExpect(status().isOk())
                    .andExpect(content().json("[]"));
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  POST /v1/api/patients/{patientId}/family-members
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("POST /{patientId}/family-members")
    class RegisterFamilyMember {

        private FamilyMemberRegistration registration;

        @BeforeEach
        void init() throws Exception {
            registration = new FamilyMemberRegistration(
                    "Jane", "Doe", "jane@example.com",
                    "555-1234", new AddressDto("123 ABC St.", null,
                    "New Market", "MD", "21774", null),
                    "Spouse", 1L
            );
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can register a family member")
        void patientRegisters() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            final FamilyMemberLinkResponse resp = mock(FamilyMemberLinkResponse.class);
            when(familyMemberService.registerFamilyMember(any(), eq(1L))).thenReturn(resp);

            mockMvc.perform(post("/v1/api/patients/10/family-members")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(registration)))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot register another family member")
        void familyMemberCannotRegister() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(post("/v1/api/patients/10/family-members")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(registration)))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  DELETE /v1/api/patients/family-members/{linkId}
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("DELETE /family-members/{linkId}")
    class RevokeFamilyMember {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can revoke family member access")
        void patientCanRevoke() throws Exception {
            mockCurrentUser(patientUser);
            doNothing().when(familyMemberService).revokeFamilyMemberAccess(5L, 1L);

            mockMvc.perform(delete("/v1/api/patients/family-members/5").with(csrf()))
                    .andExpect(status().isNoContent());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot revoke access")
        void familyMemberCannotRevoke() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(delete("/v1/api/patients/family-members/5").with(csrf()))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  GET /v1/api/patients/family-members  (convenience)
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /family-members (my family members)")
    class GetMyFamilyMembers {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can retrieve their family members")
        void patientGetsOwnFamilyMembers() throws Exception {
            mockCurrentUser(patientUser);
            when(familyMemberService.getFamilyMembersByPatient(1L)).thenReturn(List.of());

            mockMvc.perform(get("/v1/api/patients/family-members"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Non-patient gets 403")
        void nonPatientGets403() throws Exception {
            mockCurrentUser(caregiverUser);

            mockMvc.perform(get("/v1/api/patients/family-members"))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  MOOD & PAIN LOG ENDPOINTS
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Mood & Pain Log")
    class MoodPainLog {

        private MoodPainLogRequest validRequest;

        @BeforeEach
        void init() throws Exception {
            validRequest = new MoodPainLogRequest(7, 3, "Feeling okay", LocalDateTime.now().minusHours(1));
        }

        // ── POST /mood-pain-log ──────────────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can create a mood/pain log")
        void patientCreatesLog() throws Exception {
            mockCurrentUser(patientUser);
            when(moodPainLogService.createMoodPainLog(any(User.class), any(MoodPainLogRequest.class)))
                    .thenReturn(sampleLog());

            mockMvc.perform(post("/v1/api/patients/mood-pain-log")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(validRequest)))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver cannot create a mood/pain log")
        void caregiverCannotCreateLog() throws Exception {
            mockCurrentUser(caregiverUser);

            mockMvc.perform(post("/v1/api/patients/mood-pain-log")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(validRequest)))
                    .andExpect(status().isForbidden());
        }

        // ── GET /mood-pain-log ───────────────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can fetch all their logs")
        void patientFetchesLogs() throws Exception {
            mockCurrentUser(patientUser);
            when(moodPainLogService.getMoodPainLogs(patientUser)).thenReturn(List.of(sampleLog()));

            mockMvc.perform(get("/v1/api/patients/mood-pain-log"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot fetch mood/pain logs")
        void familyMemberCannotFetchLogs() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(get("/v1/api/patients/mood-pain-log"))
                    .andExpect(status().isForbidden());
        }

        // ── GET /mood-pain-log/paginated ─────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns paginated logs")
        void returnsPaginatedLogs() throws Exception {
            mockCurrentUser(patientUser);
            final Page<MoodPainLogResponse> page = new PageImpl<>(List.of(sampleLog()), PageRequest.of(0, 10), 1);
            when(moodPainLogService.getMoodPainLogsWithPagination(patientUser, 0, 10)).thenReturn(page);

            mockMvc.perform(get("/v1/api/patients/mood-pain-log/paginated?page=0&size=10"))
                    .andExpect(status().isOk());
        }

        // ── GET /mood-pain-log/latest ────────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns the latest log entry")
        void returnsLatestLog() throws Exception {
            mockCurrentUser(patientUser);
            when(moodPainLogService.getLatestMoodPainLog(patientUser)).thenReturn(sampleLog());

            mockMvc.perform(get("/v1/api/patients/mood-pain-log/latest"))
                    .andExpect(status().isOk());
        }

        // ── GET /mood-pain-log/range ─────────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns logs within date range")
        void returnsLogsInDateRange() throws Exception {
            mockCurrentUser(patientUser);
            final LocalDateTime start = LocalDateTime.now().minusDays(7);
            final LocalDateTime end = LocalDateTime.now();
            when(moodPainLogService.getMoodPainLogsByDateRange(patientUser, start, end))
                    .thenReturn(List.of(sampleLog()));

            mockMvc.perform(get("/v1/api/patients/mood-pain-log/range")
                            .param("startDate", start.toString())
                            .param("endDate", end.toString()))
                    .andExpect(status().isOk());
        }

        // ── PUT /mood-pain-log/{logId} ───────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can update a log entry")
        void patientUpdatesLog() throws Exception {
            mockCurrentUser(patientUser);
            when(moodPainLogService.updateMoodPainLog(any(User.class), eq(1L), any(MoodPainLogRequest.class)))
                    .thenReturn(sampleLog());

            mockMvc.perform(put("/v1/api/patients/mood-pain-log/1")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(validRequest)))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver cannot update a log entry")
        void caregiverCannotUpdateLog() throws Exception {
            mockCurrentUser(caregiverUser);

            mockMvc.perform(put("/v1/api/patients/mood-pain-log/1")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(validRequest)))
                    .andExpect(status().isForbidden());
        }

        // ── DELETE /mood-pain-log/{logId} ────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can delete their own log entry")
        void patientDeletesLog() throws Exception {
            mockCurrentUser(patientUser);
            doNothing().when(moodPainLogService).deleteMoodPainLog(patientUser, 1L);

            mockMvc.perform(delete("/v1/api/patients/mood-pain-log/1").with(csrf()))
                    .andExpect(status().isNoContent());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot delete a log entry")
        void familyMemberCannotDeleteLog() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(delete("/v1/api/patients/mood-pain-log/1").with(csrf()))
                    .andExpect(status().isForbidden());
        }

        // ── GET /{patientId}/mood-pain-log (caregiver view) ──────────────────────

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver with access can view patient logs")
        void caregiverViewsPatientLogs() throws Exception {
            mockCurrentUser(caregiverUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
            when(moodPainLogService.getMoodPainLogsForPatient(10L)).thenReturn(List.of(sampleLog()));

            mockMvc.perform(get("/v1/api/patients/10/mood-pain-log"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver without link cannot view patient logs")
        void caregiverWithoutLinkCannotView() throws Exception {
            mockCurrentUser(caregiverUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(false);

            mockMvc.perform(get("/v1/api/patients/10/mood-pain-log"))
                    .andExpect(status().isForbidden());
        }

        // ── GET /mood-pain-log/analytics ─────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can view their own analytics")
        void patientViewsAnalytics() throws Exception {
            mockCurrentUser(patientUser);
            final LocalDateTime start = LocalDateTime.now().minusDays(30);
            final LocalDateTime end = LocalDateTime.now();
            final MoodPainAnalyticsDTO analytics = mock(MoodPainAnalyticsDTO.class);
            when(moodPainLogService.getMoodPainAnalytics(patientUser, start, end)).thenReturn(analytics);

            mockMvc.perform(get("/v1/api/patients/mood-pain-log/analytics")
                            .param("startDate", start.toString())
                            .param("endDate", end.toString()))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver cannot view analytics endpoint")
        void caregiverCannotViewAnalytics() throws Exception {
            mockCurrentUser(caregiverUser);
            final LocalDateTime start = LocalDateTime.now().minusDays(30);
            final LocalDateTime end = LocalDateTime.now();

            mockMvc.perform(get("/v1/api/patients/mood-pain-log/analytics")
                            .param("startDate", start.toString())
                            .param("endDate", end.toString()))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  MEDICATION ENDPOINTS
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Medications")
    class Medications {

        // ── GET /{patientId}/medications ─────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can view their medications")
        void patientViewsMedications() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(medicationService.getAllMedicationsForPatient(10L)).thenReturn(List.of(sampleMedication()));

            mockMvc.perform(get("/v1/api/patients/10/medications"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver with active link can view patient medications")
        void caregiverViewsMedications() throws Exception {
            mockCurrentUser(caregiverUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
            when(medicationService.getAllMedicationsForPatient(10L)).thenReturn(List.of(sampleMedication()));

            mockMvc.perform(get("/v1/api/patients/10/medications"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member with active link can view patient medications")
        void familyMemberViewsMedications() throws Exception {
            mockCurrentUser(familyUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(familyMemberService.hasAccessToPatient(3L, 1L)).thenReturn(true);
            when(medicationService.getAllMedicationsForPatient(10L)).thenReturn(List.of(sampleMedication()));

            mockMvc.perform(get("/v1/api/patients/10/medications"))
                    .andExpect(status().isOk());
        }

        // ── POST /{patientId}/medications ────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can add a medication")
        void patientAddsMedication() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(medicationService.createMedication(any(MedicationDTO.class))).thenReturn(sampleMedication());

            mockMvc.perform(post("/v1/api/patients/10/medications")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleMedication())))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot add a medication — read-only")
        void familyMemberCannotAddMedication() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(post("/v1/api/patients/10/medications")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleMedication())))
                    .andExpect(status().isForbidden());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Caregiver with active link can add a medication")
        void caregiverAddsMedication() throws Exception {
            mockCurrentUser(caregiverUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
            when(medicationService.createMedication(any(MedicationDTO.class))).thenReturn(sampleMedication());

            mockMvc.perform(post("/v1/api/patients/10/medications")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(sampleMedication())))
                    .andExpect(status().isOk());
        }

        // ── DELETE /{patientId}/medications/{medicationId} ───────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can deactivate a medication")
        void patientDeactivatesMedication() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            doNothing().when(medicationService).deactivateMedication(10L, 1L);

            mockMvc.perform(delete("/v1/api/patients/10/medications/1").with(csrf()))
                    .andExpect(status().isNoContent());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot deactivate a medication — read-only")
        void familyMemberCannotDeactivateMedication() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(delete("/v1/api/patients/10/medications/1").with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can mark medication as taken")
        void patientMarksMedicationTaken() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(medicationService.updateMedicationLastTaken(eq(10L), eq(1L), any()))
                    .thenReturn(sampleMedication());

            mockMvc.perform(put("/v1/api/patients/10/medications/1/last-taken")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"lastTaken\":\"2026-03-12T12:00:00Z\"}"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can clear medication taken status")
        void patientClearsMedicationTakenStatus() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(medicationService.clearMedicationLastTaken(10L, 1L))
                    .thenReturn(sampleMedication());

            mockMvc.perform(delete("/v1/api/patients/10/medications/1/last-taken")
                            .with(csrf()))
                    .andExpect(status().isNoContent());
        }

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("Family member cannot mark medication as taken")
        void familyMemberCannotMarkMedicationTaken() throws Exception {
            mockCurrentUser(familyUser);

            mockMvc.perform(put("/v1/api/patients/10/medications/1/last-taken")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"lastTaken\":\"2026-03-12T12:00:00Z\"}"))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  PATIENT PROFILE ENDPOINTS
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Patient Profile")
    class PatientProfile {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can get their own profile")
        void patientGetsOwnProfile() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            final PatientProfileDTO dto = mock(PatientProfileDTO.class);
            when(patientService.getPatientProfile(10L)).thenReturn(Optional.of(dto));

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns 404 when profile not found")
        void returns404WhenNotFound() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(patientService.getPatientProfile(10L)).thenReturn(Optional.empty());

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isNotFound());
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can update their own profile")
        void patientUpdatesProfile() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            // PatientProfileUpdateDTO updateDTO = mock(PatientProfileUpdateDTO.class);
            final PatientProfileDTO updatedDTO = mock(PatientProfileDTO.class);
            when(patientService.updatePatientProfile(eq(10L), any())).thenReturn(updatedDTO);

            mockMvc.perform(put("/v1/api/patients/10/profile")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  ENHANCED PROFILE
    // ════════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Enhanced Patient Profile")
    class EnhancedProfile {

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Patient can get their enhanced profile")
        void patientGetsEnhancedProfile() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            final EnhancedPatientProfileDTO dto = mock(EnhancedPatientProfileDTO.class);
            when(patientService.getEnhancedPatientProfile(10L)).thenReturn(Optional.of(dto));

            mockMvc.perform(get("/v1/api/patients/10/profile/enhanced"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Returns 404 when enhanced profile not found")
        void returns404() throws Exception {
            mockCurrentUser(patientUser);
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(patientService.getEnhancedPatientProfile(10L)).thenReturn(Optional.empty());

            mockMvc.perform(get("/v1/api/patients/10/profile/enhanced"))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("hasAccessToPatient() — via GET /{patientId}/profile")
    class HasAccessToPatient {

        // ── PATIENT role ─────────────────────────────────────────────────────────
        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("PATIENT accessing another patient's record — returns false")
        void patient_otherRecord_denied() throws Exception {
            final User otherPatientUser = buildUser(99L, "other@test.com", Role.PATIENT);
            final Patient otherPatient = new Patient();
            otherPatient.setId(20L);
            otherPatient.setUser(otherPatientUser);

            when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patientUser));
            when(patientService.getPatientById(20L)).thenReturn(otherPatient);

            mockMvc.perform(get("/v1/api/patients/20/profile"))
                    .andExpect(status().isForbidden());
        }

        // ── CAREGIVER role ───────────────────────────────────────────────────────

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("CAREGIVER found in patient's caregiver list — returns true")
        void caregiver_inList_granted() throws Exception {
            final Caregiver caregiver = new Caregiver();
            caregiver.setUser(caregiverUser); // caregiverUser.getId() == 2L

            when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(patientService.getCaregiversByPatient(10L)).thenReturn(List.of(caregiver));
            when(patientService.getPatientProfile(10L)).thenReturn(Optional.of(mock(PatientProfileDTO.class)));

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("CAREGIVER not in patient's caregiver list — returns false")
        void caregiver_notInList_denied() throws Exception {
            final User otherCaregiverUser = buildUser(99L, "other-caregiver@test.com", Role.CAREGIVER);
            final Caregiver unrelatedCaregiver = new Caregiver();
            unrelatedCaregiver.setUser(otherCaregiverUser);

            when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(patientService.getCaregiversByPatient(10L)).thenReturn(List.of(unrelatedCaregiver));

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isForbidden());
        }

        // ── FAMILY_MEMBER role ───────────────────────────────────────────────────

        @Test
        @WithMockUser(username = "family@test.com")
        @DisplayName("FAMILY_MEMBER found in patient's family member list — returns true")
        void familyMember_inList_granted() throws Exception {
            final FamilyMemberLinkResponse link = mock(FamilyMemberLinkResponse.class);
            when(link.familyUserId()).thenReturn(3L); // matches familyUser.getId()

            when(userRepository.findByEmail("family@test.com")).thenReturn(Optional.of(familyUser));
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(familyMemberService.getFamilyMembersByPatient(10L)).thenReturn(List.of(link));
            when(patientService.getPatientProfile(10L)).thenReturn(Optional.of(mock(PatientProfileDTO.class)));

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isOk());
        }

        // ── ADMIN role ───────────────────────────────────────────────────────────

        @Test
        @WithMockUser(username = "admin@test.com")
        @DisplayName("ADMIN always gets access — returns true")
        void admin_alwaysGranted() throws Exception {
            when(userRepository.findByEmail("admin@test.com")).thenReturn(Optional.of(adminUser));
            when(patientService.getPatientById(10L)).thenReturn(patient);
            when(patientService.getPatientProfile(10L)).thenReturn(Optional.of(mock(PatientProfileDTO.class)));

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isOk());
        }

        // ── Patient not found ────────────────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("getPatientById returns null — patientOpt.isEmpty() branch — returns false")
        void patientNotFound_denied() throws Exception {
            when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patientUser));
            when(patientService.getPatientById(10L)).thenReturn(null);

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isForbidden());
        }

        // ── catch(Exception) block ───────────────────────────────────────────────

        @Test
        @WithMockUser(username = "patient@test.com")
        @DisplayName("Unexpected exception in access check — catch block returns false")
        void unexpectedException_caught_returnsFalse() throws Exception {
            when(userRepository.findByEmail("patient@test.com"))
                    .thenThrow(new RuntimeException("DB connection lost"));

            mockMvc.perform(get("/v1/api/patients/10/profile"))
                    .andExpect(status().isForbidden());

            verifyNoInteractions(patientService);
        }
    }
}
