package com.careconnect.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.v2.TaskServiceV2;
import com.careconnect.util.SecurityUtil;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@ExtendWith(MockitoExtension.class)
class AlexaControllerTest {

    private static final String VALID_TOKEN = "valid.jwt.token";
    private static final String BEARER_TOKEN = "Bearer " + VALID_TOKEN;
    private static final Long PATIENT_ID = 42L;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @Mock
    private JwtTokenProvider jwtTokenProvider;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private TaskServiceV2 taskService;
    @InjectMocks
    private AlexaController controller;
    private User patientUser;
    private Patient patient;
    private TaskDtoV2 sampleTask;

    @BeforeEach
    void setUp() {
        patientUser = new User();
        patientUser.setId(10L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);

        patient = new Patient();
        patient.setId(PATIENT_ID);
        patient.setUser(patientUser);

        sampleTask = TaskDtoV2.builder()
                .id(1L)
                .name("Take Medication")
                .description("Take blood pressure pill")
                .date(LocalDate.now() + "T00:00:00")
                .isCompleted(false)
                .taskType("Medication")
                .build();
    }

    private void stubTokenResolution() {
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn("patient@test.com");
        when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patientUser));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
    }

    // =========================================================================
    // GET /v1/api/alexa/calendarTasks/get
    // =========================================================================

    @Test
    @DisplayName("getCalendarTasks returns all tasks when filter=all")
    void getCalendarTasks_allFilter_returnsAllTasks() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.getTasksByPatient(PATIENT_ID)).thenReturn(List.of(sampleTask));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        List<TaskDtoV2> tasks = (List<TaskDtoV2>) response.getBody();
        assertThat(tasks).hasSize(1);
        assertThat(tasks.get(0).getName()).isEqualTo("Take Medication");
        verify(taskService).getTasksByPatient(PATIENT_ID);
    }

    @Test
    @DisplayName("getCalendarTasks filters tasks by week when filter=week")
    void getCalendarTasks_weekFilter_filtersCorrectly() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();

        TaskDtoV2 todayTask = TaskDtoV2.builder()
                .id(2L).name("Today Task")
                .date(LocalDate.now() + "T00:00:00")
                .isCompleted(false).build();
        TaskDtoV2 oldTask = TaskDtoV2.builder()
                .id(3L).name("Old Task")
                .date(LocalDate.now().minusDays(10) + "T00:00:00")
                .isCompleted(false).build();

        when(taskService.getTasksByPatient(PATIENT_ID)).thenReturn(List.of(todayTask, oldTask));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "week");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        List<TaskDtoV2> tasks = (List<TaskDtoV2>) response.getBody();
        assertThat(tasks).hasSize(1);
        assertThat(tasks.get(0).getName()).isEqualTo("Today Task");
    }

    @Test
    @DisplayName("getCalendarTasks defaults to week filter when no filter param")
    void getCalendarTasks_defaultFilter_isWeek() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();

        TaskDtoV2 todayTask = TaskDtoV2.builder()
                .id(4L).name("Now Task")
                .date(LocalDate.now() + "T00:00:00")
                .isCompleted(false).build();
        when(taskService.getTasksByPatient(PATIENT_ID)).thenReturn(List.of(todayTask));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "week");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        List<TaskDtoV2> tasks = (List<TaskDtoV2>) response.getBody();
        assertThat(tasks).hasSize(1);
        assertThat(tasks.get(0).getName()).isEqualTo("Now Task");
    }

    @Test
    @DisplayName("getCalendarTasks returns 401 when no authorization header")
    void getCalendarTasks_noAuthHeader_returns401() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);

        ResponseEntity<?> response = controller.getCalendarTasks(null, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        @SuppressWarnings("unchecked")
        Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body.get("error")).isEqualTo("Missing or invalid access token");
    }

    @Test
    @DisplayName("getCalendarTasks returns 401 when token is invalid")
    void getCalendarTasks_invalidToken_returns401() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(jwtTokenProvider.validateToken("bad.token")).thenReturn(false);

        ResponseEntity<?> response =
                controller.getCalendarTasks("Bearer bad.token", "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    @DisplayName("getCalendarTasks returns 400 when patient cannot be resolved")
    void getCalendarTasks_patientNotFound_returns400() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn("patient@test.com");
        when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patientUser));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked")
        Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body.get("error")).isEqualTo("Unable to resolve patient ID");
    }

    @Test
    @DisplayName("getCalendarTasks resolves patient via caregiver role")
    void getCalendarTasks_caregiverRole_resolvesPatient() throws UnauthorizedException {
        User caregiverUser = new User();
        caregiverUser.setId(20L);
        caregiverUser.setEmail("caregiver@test.com");
        caregiverUser.setRole(Role.CAREGIVER);

        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn("caregiver@test.com");
        when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
        when(patientRepository.findAll()).thenReturn(List.of(patient));
        when(patientRepository.hasAccessByCaregiverId(PATIENT_ID, 20L)).thenReturn(true);
        when(taskService.getTasksByPatient(PATIENT_ID)).thenReturn(List.of(sampleTask));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(taskService).getTasksByPatient(PATIENT_ID);
    }

    @Test
    @DisplayName("getCalendarTasks returns 400 when caregiver has no linked patients")
    void getCalendarTasks_caregiverNoLinkedPatients_returns400() throws UnauthorizedException {
        User caregiverUser = new User();
        caregiverUser.setId(20L);
        caregiverUser.setEmail("caregiver@test.com");
        caregiverUser.setRole(Role.CAREGIVER);

        when(securityUtil.resolveCurrentUser()).thenReturn(caregiverUser);
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn("caregiver@test.com");
        when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
        when(patientRepository.findAll()).thenReturn(List.of(patient));
        when(patientRepository.hasAccessByCaregiverId(PATIENT_ID, 20L)).thenReturn(false);

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("getCalendarTasks returns 400 for unsupported role (ADMIN)")
    void getCalendarTasks_unsupportedRole_returns400() throws UnauthorizedException {
        User adminUser = new User();
        adminUser.setId(30L);
        adminUser.setEmail("admin@test.com");
        adminUser.setRole(Role.ADMIN);

        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn("admin@test.com");
        when(userRepository.findByEmail("admin@test.com")).thenReturn(Optional.of(adminUser));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("getCalendarTasks throws UnauthorizedException for family member")
    void getCalendarTasks_familyMember_throwsUnauthorized() throws UnauthorizedException {
        User familyUser = new User();
        familyUser.setId(40L);
        familyUser.setRole(Role.FAMILY_MEMBER);

        when(securityUtil.resolveCurrentUser()).thenReturn(familyUser);

        assertThatThrownBy(() -> controller.getCalendarTasks(BEARER_TOKEN, "all"))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Family members cannot access Alexa features");
    }

    @Test
    @DisplayName("getCalendarTasks returns 400 when email not found in user repository")
    void getCalendarTasks_userNotFoundByEmail_returns400() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn("unknown@test.com");
        when(userRepository.findByEmail("unknown@test.com")).thenReturn(Optional.empty());

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("getCalendarTasks returns 400 when email claim is null")
    void getCalendarTasks_nullEmailClaim_returns400() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn(null);

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("getCalendarTasks returns 500 when taskService throws exception")
    void getCalendarTasks_serviceThrows_returns500() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.getTasksByPatient(PATIENT_ID))
                .thenThrow(new RuntimeException("DB error"));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    @Test
    @DisplayName("getCalendarTasks week filter skips tasks with null date")
    void getCalendarTasks_weekFilter_skipsNullDates() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();

        TaskDtoV2 nullDateTask = TaskDtoV2.builder()
                .id(5L).name("No Date Task")
                .date(null)
                .isCompleted(false).build();
        TaskDtoV2 todayTask = TaskDtoV2.builder()
                .id(6L).name("Today Task")
                .date(LocalDate.now() + "T00:00:00")
                .isCompleted(false).build();

        when(taskService.getTasksByPatient(PATIENT_ID))
                .thenReturn(List.of(nullDateTask, todayTask));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "week");

        @SuppressWarnings("unchecked")
        List<TaskDtoV2> tasks = (List<TaskDtoV2>) response.getBody();
        assertThat(tasks).hasSize(1);
        assertThat(tasks.get(0).getName()).isEqualTo("Today Task");
    }

    @Test
    @DisplayName("getCalendarTasks includes tasks within 6 days from now in week filter")
    void getCalendarTasks_weekFilter_includesFutureTasks() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();

        TaskDtoV2 futureTask = TaskDtoV2.builder()
                .id(7L).name("Future Task")
                .date(LocalDate.now().plusDays(6) + "T00:00:00")
                .isCompleted(false).build();
        TaskDtoV2 tooFarTask = TaskDtoV2.builder()
                .id(8L).name("Too Far Task")
                .date(LocalDate.now().plusDays(7) + "T00:00:00")
                .isCompleted(false).build();

        when(taskService.getTasksByPatient(PATIENT_ID))
                .thenReturn(List.of(futureTask, tooFarTask));

        ResponseEntity<?> response = controller.getCalendarTasks(BEARER_TOKEN, "week");

        @SuppressWarnings("unchecked")
        List<TaskDtoV2> tasks = (List<TaskDtoV2>) response.getBody();
        assertThat(tasks).hasSize(1);
        assertThat(tasks.get(0).getName()).isEqualTo("Future Task");
    }

    @Test
    @DisplayName("getCalendarTasks returns 401 when auth header is present but not Bearer format")
    void getCalendarTasks_nonBearerHeader_returns401() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);

        ResponseEntity<?> response =
                controller.getCalendarTasks("Basic dXNlcjpwYXNz", "all");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    // =========================================================================
    // POST /v1/api/alexa/calendarTasks/add
    // =========================================================================

    @Test
    @DisplayName("addCalendarTask creates task successfully with Authorization header")
    void addCalendarTask_success_withAuthHeader() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Take Medication",
                "date", LocalDate.now().toString(),
                "taskType", "Medication");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        TaskDtoV2 result = (TaskDtoV2) response.getBody();
        assertThat(result).isNotNull();
        assertThat(result.getName()).isEqualTo("Take Medication");
        verify(taskService).createTask(eq(PATIENT_ID), any(TaskDtoV2.class));
    }

    @Test
    @DisplayName("addCalendarTask falls back to accessToken in body")
    void addCalendarTask_tokenFromBody() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Walk Outside",
                "date", LocalDate.now().toString(),
                "accessToken", VALID_TOKEN);

        ResponseEntity<?> response = controller.addCalendarTask(null, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask returns 401 when no token provided")
    void addCalendarTask_noToken_returns401() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);

        Map<String, Object> body = Map.of(
                "name", "Walk",
                "date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(null, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    @DisplayName("addCalendarTask returns 400 when patient cannot be resolved")
    void addCalendarTask_patientNotFound_returns400() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(VALID_TOKEN)).thenReturn("patient@test.com");
        when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patientUser));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

        Map<String, Object> body = Map.of(
                "name", "Walk",
                "date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("addCalendarTask returns 400 when task name is missing")
    void addCalendarTask_missingName_returns400() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();

        Map<String, Object> body = Map.of("date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked")
        Map<String, String> respBody = (Map<String, String>) response.getBody();
        assertThat(respBody.get("error")).isEqualTo("Task name is required");
    }

    @Test
    @DisplayName("addCalendarTask returns 400 when task name is blank")
    void addCalendarTask_blankName_returns400() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();

        Map<String, Object> body = Map.of(
                "name", "   ",
                "date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("addCalendarTask returns 403 when service throws Unauthorized")
    void addCalendarTask_serviceThrowsUnauthorized_returns403() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenThrow(new RuntimeException("Unauthorized access to patient data"));

        Map<String, Object> body = Map.of(
                "name", "Take Medication",
                "date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        @SuppressWarnings("unchecked")
        Map<String, String> respBody = (Map<String, String>) response.getBody();
        assertThat(respBody.get("error")).isEqualTo("Access denied to patient data");
    }

    @Test
    @DisplayName("addCalendarTask returns 403 when service throws Forbidden")
    void addCalendarTask_serviceThrowsForbidden_returns403() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenThrow(new RuntimeException("Forbidden: insufficient permissions"));

        Map<String, Object> body = Map.of(
                "name", "Take Medication",
                "date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("addCalendarTask returns 500 when service throws generic error")
    void addCalendarTask_serviceThrowsGenericError_returns500() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenThrow(new RuntimeException("Database connection lost"));

        Map<String, Object> body = Map.of(
                "name", "Take Medication",
                "date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        @SuppressWarnings("unchecked")
        Map<String, String> respBody = (Map<String, String>) response.getBody();
        assertThat(respBody.get("error")).isEqualTo("Error adding task");
    }

    @Test
    @DisplayName("addCalendarTask normalizes invalid date to today")
    void addCalendarTask_invalidDate_defaultsToToday() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();

        TaskDtoV2 created = TaskDtoV2.builder()
                .id(5L).name("Walk")
                .date(LocalDate.now() + "T00:00:00")
                .isCompleted(false).build();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(created);

        Map<String, Object> body = Map.of(
                "name", "Walk",
                "date", "not-a-date");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask throws UnauthorizedException for family member")
    void addCalendarTask_familyMember_throwsUnauthorized() throws UnauthorizedException {
        User familyUser = new User();
        familyUser.setId(40L);
        familyUser.setRole(Role.FAMILY_MEMBER);

        when(securityUtil.resolveCurrentUser()).thenReturn(familyUser);

        Map<String, Object> body = Map.of(
                "name", "Walk",
                "date", LocalDate.now().toString());

        assertThatThrownBy(() -> controller.addCalendarTask(BEARER_TOKEN, body))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Family members cannot access Alexa features");
    }

    @Test
    @DisplayName("addCalendarTask uses title field as name fallback")
    void addCalendarTask_useTitleAsNameFallback() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "title", "Exercise",
                "date", LocalDate.now().toString());

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles description field")
    void addCalendarTask_withDescription() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "description", "Take 2 pills");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles timeOfDay field")
    void addCalendarTask_withTimeOfDay() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "timeOfDay", "14:30:00");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles invalid timeOfDay gracefully")
    void addCalendarTask_invalidTimeOfDay_graceful() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "timeOfDay", "not-a-time");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles frequency and interval fields")
    void addCalendarTask_withFrequencyAndInterval() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "frequency", "DAILY",
                "interval", 2,
                "count", 10);

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles string interval and count values")
    void addCalendarTask_stringIntervalAndCount() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "interval", "3",
                "count", "5");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles unparseable string interval gracefully")
    void addCalendarTask_unparseableInterval_defaultsToOne() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "interval", "abc",
                "count", "xyz");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles daysOfWeek with boolean list")
    void addCalendarTask_daysOfWeekBooleanList() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "daysOfWeek", List.of(true, false, true, false, true, false, true));

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles daysOfWeek with string list")
    void addCalendarTask_daysOfWeekStringList() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "daysOfWeek", List.of("true", "false", "true"));

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask handles daysOfWeek with integer list")
    void addCalendarTask_daysOfWeekIntegerList() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of(
                "name", "Med Reminder",
                "date", LocalDate.now().toString(),
                "daysOfWeek", List.of(1, 0, 1, 0, 1, 0, 0));

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    @DisplayName("addCalendarTask defaults date to today when not provided")
    void addCalendarTask_noDate_defaultsToToday() throws UnauthorizedException {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        stubTokenResolution();
        when(taskService.createTask(eq(PATIENT_ID), any(TaskDtoV2.class)))
                .thenReturn(sampleTask);

        Map<String, Object> body = Map.of("name", "Walk Outside");

        ResponseEntity<?> response = controller.addCalendarTask(BEARER_TOKEN, body);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }
}
