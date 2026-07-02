package com.careconnect.controller;

import com.careconnect.dto.CheckInCreateResponseDTO;
import com.careconnect.dto.CheckInSummaryDTO;
import com.careconnect.dto.QuestionDTO;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AnswerSubmissionService;
import com.careconnect.service.CheckInSnapshotService;
import com.careconnect.service.QuestionService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.OffsetDateTime;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(CheckInQuestionController.class)
@DisplayName("CheckInQuestionController Access Tests")
class CheckInQuestionControllerRbacTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private AnswerSubmissionService answerSubmissionService;

    @MockitoBean
    private QuestionService questionService;

    @MockitoBean
    private CheckInSnapshotService checkInSnapshotService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    private User adminUser;
    private User caregiverUser;
    private User patientUser;
    private User familyMemberUser;

    @BeforeEach
    void setUp() {
        adminUser = makeUser(1L, Role.ADMIN);
        caregiverUser = makeUser(2L, Role.CAREGIVER);
        patientUser = makeUser(3L, Role.PATIENT);
        familyMemberUser = makeUser(4L, Role.FAMILY_MEMBER);
    }

    private User makeUser(Long id, Role role) {
        final User u = new User();
        u.setId(id);
        u.setEmail("user" + id + "@test.com");
        u.setRole(role);
        return u;
    }

    @Test
    @WithMockUser(username = "admin@test.com")
    @DisplayName("ADMIN can read check-in snapshot questions")
    void admin_canReadSnapshotQuestions() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(checkInSnapshotService.getPatientIdForCheckIn(1L)).thenReturn(3L);
        when(checkInSnapshotService.getSnapshotQuestions(1L)).thenReturn(List.of(
                new QuestionDTO(1L, "How are you?", "TEXT", true, true, 1)));

        mockMvc.perform(get("/api/checkins/1/questions"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].prompt").value("How are you?"));

        verify(securityUtil).resolveCurrentUser();
        verify(authorizationService).requirePatientAccess(adminUser, 3L);
        verify(checkInSnapshotService).getSnapshotQuestions(1L);
    }

    @Test
    @WithMockUser(username = "caregiver@test.com")
    @DisplayName("CAREGIVER can read snapshot questions")
    void caregiver_canReadSnapshotQuestions() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        when(checkInSnapshotService.getPatientIdForCheckIn(1L)).thenReturn(3L);
        when(checkInSnapshotService.getSnapshotQuestions(1L)).thenReturn(List.of());

        mockMvc.perform(get("/api/checkins/1/questions"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));

        verify(securityUtil).resolveCurrentUser();
        verify(authorizationService).requirePatientAccess(caregiverUser, 3L);
        verify(checkInSnapshotService).getSnapshotQuestions(1L);
    }

    @Test
    @WithMockUser(username = "patient@test.com")
    @DisplayName("PATIENT can read snapshot questions")
    void patient_canReadSnapshotQuestions() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(checkInSnapshotService.getPatientIdForCheckIn(1L)).thenReturn(3L);
        when(checkInSnapshotService.getSnapshotQuestions(1L)).thenReturn(List.of());

        mockMvc.perform(get("/api/checkins/1/questions"))
                .andExpect(status().isOk());

        verify(securityUtil).resolveCurrentUser();
        verify(authorizationService).requirePatientAccess(patientUser, 3L);
    }

    @Test
    @WithMockUser(username = "family@test.com")
    @DisplayName("FAMILY_MEMBER can read snapshot questions")
    void familyMember_canReadSnapshotQuestions() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(familyMemberUser);
        when(checkInSnapshotService.getPatientIdForCheckIn(1L)).thenReturn(3L);
        when(checkInSnapshotService.getSnapshotQuestions(1L)).thenReturn(List.of());

        mockMvc.perform(get("/api/checkins/1/questions"))
                .andExpect(status().isOk());

        verify(securityUtil).resolveCurrentUser();
        verify(authorizationService).requirePatientAccess(familyMemberUser, 3L);
    }

    @Test
    @WithMockUser(username = "patient@test.com")
    @DisplayName("PATIENT can list own patient check-ins")
    void patient_canListPatientCheckIns() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(checkInSnapshotService.listCheckInsForPatient(3L)).thenReturn(List.of(
                new CheckInSummaryDTO(10L, 3L, OffsetDateTime.parse("2026-06-26T10:00:00Z"), null, 2)));

        mockMvc.perform(get("/api/checkins/patients/3"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].checkInId").value(10));

        verify(securityUtil).resolveCurrentUser();
        verify(authorizationService).requirePatientAccess(patientUser, 3L);
        verify(checkInSnapshotService).listCheckInsForPatient(3L);
    }

    @Test
    @WithMockUser(username = "patient@test.com")
    @DisplayName("PATIENT cannot list another patient's check-ins")
    void patient_cannotListOtherPatientCheckIns() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Patients can only access their own data"))
                .when(authorizationService).requirePatientAccess(patientUser, 9L);

        mockMvc.perform(get("/api/checkins/patients/9"))
                .andExpect(status().isForbidden());

        verify(securityUtil).resolveCurrentUser();
        verify(authorizationService).requirePatientAccess(patientUser, 9L);
        verifyNoInteractions(checkInSnapshotService);
    }

    @Test
    @WithMockUser(username = "admin@test.com")
    @DisplayName("Versioned path returns legacy global active questions")
    void versionedPath_usesLegacyQuestionService() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(checkInSnapshotService.getPatientIdForCheckIn(1L)).thenReturn(3L);
        when(questionService.findActiveOrdered()).thenReturn(List.of(
                new QuestionDTO(1L, "Legacy", "TEXT", true, true, 1)));

        mockMvc.perform(get("/v1/api/checkins/1/questions"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].prompt").value("Legacy"));

        verify(authorizationService).requirePatientAccess(adminUser, 3L);
        verify(questionService).findActiveOrdered();
    }

    @Test
    @WithMockUser(username = "admin@test.com")
    @DisplayName("ADMIN can create check-ins with snapshots")
    void admin_canCreateCheckInWithSnapshots() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(checkInSnapshotService.createCheckInWithSnapshot(any())).thenReturn(
                new CheckInCreateResponseDTO(10L, 3L, OffsetDateTime.parse("2026-06-26T10:00:00Z"), 2)
        );

        mockMvc.perform(post("/api/checkins")
                        .with(csrf())
                        .contentType("application/json")
                        .content("{\"patientId\":3,\"selectedQuestionIds\":[1,2]}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.checkInId").value(10));

        verify(securityUtil).resolveCurrentUser();
        verify(authorizationService).requirePatientAccess(adminUser, 3L);
        verify(checkInSnapshotService).createCheckInWithSnapshot(any());
    }

    @Test
    @WithMockUser(username = "unknown@test.com")
    @DisplayName("Unknown user in DB fails before service access")
    void unknownUser_triggersRuntimeException() throws Exception {
        when(securityUtil.resolveCurrentUser())
                .thenThrow(new RuntimeException("User not found: unknown@test.com"));

        mockMvc.perform(get("/api/checkins/1/questions"))
                .andExpect(status().isInternalServerError());

        verify(securityUtil).resolveCurrentUser();
        verifyNoInteractions(questionService, checkInSnapshotService);
    }
}
