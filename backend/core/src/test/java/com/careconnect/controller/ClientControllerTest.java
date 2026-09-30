package com.careconnect.controller;

import com.careconnect.model.BehavioralIncident;
import com.careconnect.model.Caregiver;
import com.careconnect.model.ClientEvent;
import com.careconnect.model.IncidentAction;
import com.careconnect.model.IncidentReport;
import com.careconnect.model.ActivityLog;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.ActivityLogRepository;
import com.careconnect.repository.BehavioralIncidentRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.ClientEventRepository;
import com.careconnect.repository.IncidentReportRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.PatientService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.hamcrest.Matchers.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(ClientController.class)
@DisplayName("ClientController – in-home residential support endpoints")
class ClientControllerTest {

    private static final Long CLIENT_ID = 10L;
    private static final Long CAREGIVER_USER_ID = 42L;
    private static final Long CAREGIVER_ID = 99L;
    private static final Long PATIENT_USER_ID = 1L;
    @Autowired
    private MockMvc mockMvc;
    @MockitoBean
    private PatientService patientService;
    @MockitoBean
    private UserRepository userRepository;
    @MockitoBean
    private CaregiverPatientLinkService caregiverPatientLinkService;
    @MockitoBean
    private FamilyMemberService familyMemberService;
    @MockitoBean
    private CaregiverRepository caregiverRepository;
    @MockitoBean
    private BehavioralIncidentRepository behavioralIncidentRepository;
    @MockitoBean
    private IncidentReportRepository incidentReportRepository;
    @MockitoBean
    private ClientEventRepository clientEventRepository;
    @MockitoBean
    private ActivityLogRepository activityLogRepository;
    private ObjectMapper objectMapper;
    private User caregiverUser;
    private Patient patient;
    private Caregiver caregiver;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

        caregiverUser = new User();
        caregiverUser.setId(CAREGIVER_USER_ID);
        caregiverUser.setEmail("caregiver@test.com");
        caregiverUser.setName("Test Caregiver");
        caregiverUser.setRole(Role.CAREGIVER);

        User patientUser = new User();
        patientUser.setId(PATIENT_USER_ID);

        patient = new Patient();
        patient.setId(CLIENT_ID);
        patient.setUser(patientUser);

        caregiver = new Caregiver();
        caregiver.setId(CAREGIVER_ID);
        caregiver.setUser(caregiverUser);
    }

    /**
     * Sets up standard caregiver-access mocks used by most tests.
     */
    private void stubCaregiverAccess() {
        when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
        when(patientService.getPatientById(CLIENT_ID)).thenReturn(patient);
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID)).thenReturn(true);
    }

    // =========================================================
    // POST /{id}/behavioral-incidents
    // =========================================================

    @Nested
    @DisplayName("POST /{id}/behavioral-incidents")
    class CreateBehavioralIncident {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 201 with valid payload")
        void validRequest_returns201() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            BehavioralIncident saved = BehavioralIncident.builder()
                    .id(1L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .observedBehavior("Client refused to eat").occurredAt(LocalDateTime.now())
                    .createdBy(CAREGIVER_USER_ID).createdAt(LocalDateTime.now()).build();
            when(behavioralIncidentRepository.save(any(BehavioralIncident.class))).thenReturn(saved);

            String body = "{\"observed_behavior\":\"Client refused to eat\",\"occurred_at\":\"2026-03-10T09:00:00\"}";

            mockMvc.perform(post("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.clientId").value(CLIENT_ID));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("caregiverId and createdBy are set from session, not body")
        void caregiverIdFromSession() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            when(behavioralIncidentRepository.save(any(BehavioralIncident.class)))
                    .thenAnswer(inv -> inv.getArgument(0));

            String body = "{\"observed_behavior\":\"Aggression\",\"occurred_at\":\"2026-03-10T09:00:00\"}";

            mockMvc.perform(post("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isCreated());

            var captor = org.mockito.ArgumentCaptor.forClass(BehavioralIncident.class);
            verify(behavioralIncidentRepository).save(captor.capture());
            BehavioralIncident incident = captor.getValue();
            org.assertj.core.api.Assertions.assertThat(incident.getCaregiverId()).isEqualTo(CAREGIVER_ID);
            org.assertj.core.api.Assertions.assertThat(incident.getCreatedBy()).isEqualTo(CAREGIVER_USER_ID);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when observed_behavior is missing")
        void missingObservedBehavior_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"occurred_at\":\"2026-03-10T09:00:00\"}";

            mockMvc.perform(post("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when occurred_at is missing")
        void missingOccurredAt_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"observed_behavior\":\"Client refused to eat\"}";

            mockMvc.perform(post("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when occurred_at is invalid ISO-8601")
        void invalidOccurredAt_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"observed_behavior\":\"Aggression\",\"occurred_at\":\"not-a-date\"}";

            mockMvc.perform(post("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when user is not a caregiver")
        void notACaregiver_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.empty());

            String body = "{\"observed_behavior\":\"Aggression\",\"occurred_at\":\"2026-03-10T09:00:00\"}";

            mockMvc.perform(post("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("trigger_notes is optional and stored when provided")
        void withTriggerNotes_returns201() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));
            when(behavioralIncidentRepository.save(any(BehavioralIncident.class)))
                    .thenAnswer(inv -> inv.getArgument(0));

            String body = "{\"observed_behavior\":\"Yelling\",\"occurred_at\":\"2026-03-10T09:00:00\",\"trigger_notes\":\"Before meals\"}";

            mockMvc.perform(post("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isCreated());

            var captor = org.mockito.ArgumentCaptor.forClass(BehavioralIncident.class);
            verify(behavioralIncidentRepository).save(captor.capture());
            org.assertj.core.api.Assertions.assertThat(captor.getValue().getTriggerNotes()).isEqualTo("Before meals");
        }
    }

    // =========================================================
    // GET /{id}/behavioral-incidents
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/behavioral-incidents")
    class ListBehavioralIncidents {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with list of incidents")
        void returns200WithList() throws Exception {
            stubCaregiverAccess();
            BehavioralIncident inc = BehavioralIncident.builder()
                    .id(1L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .observedBehavior("Hitting").occurredAt(LocalDateTime.now())
                    .createdBy(CAREGIVER_USER_ID).createdAt(LocalDateTime.now()).build();
            when(behavioralIncidentRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(List.of(inc));

            mockMvc.perform(get("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(1)))
                    .andExpect(jsonPath("$[0].observedBehavior").value("Hitting"));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with empty list when no incidents exist")
        void returns200WithEmptyList() throws Exception {
            stubCaregiverAccess();
            when(behavioralIncidentRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());

            mockMvc.perform(get("/v1/api/clients/{id}/behavioral-incidents", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(0)));
        }
    }

    // =========================================================
    // GET /{id}/behavioral-incidents/{incidentId}
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/behavioral-incidents/{incidentId}")
    class GetBehavioralIncident {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 when incident exists and belongs to client")
        void found_returns200() throws Exception {
            stubCaregiverAccess();
            BehavioralIncident inc = BehavioralIncident.builder()
                    .id(5L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .observedBehavior("Self-soothing").occurredAt(LocalDateTime.now())
                    .createdBy(CAREGIVER_USER_ID).createdAt(LocalDateTime.now()).build();
            when(behavioralIncidentRepository.findById(5L)).thenReturn(Optional.of(inc));

            mockMvc.perform(get("/v1/api/clients/{id}/behavioral-incidents/{incidentId}", CLIENT_ID, 5L)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(5));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 404 when incident does not exist")
        void notFound_returns404() throws Exception {
            stubCaregiverAccess();
            when(behavioralIncidentRepository.findById(999L)).thenReturn(Optional.empty());

            mockMvc.perform(get("/v1/api/clients/{id}/behavioral-incidents/{incidentId}", CLIENT_ID, 999L)
                            .with(csrf()))
                    .andExpect(status().isNotFound());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 403 when incident belongs to a different client")
        void wrongClient_returns403() throws Exception {
            stubCaregiverAccess();
            BehavioralIncident inc = BehavioralIncident.builder()
                    .id(7L).clientId(999L)  // different client
                    .caregiverId(CAREGIVER_ID).observedBehavior("Wandering")
                    .occurredAt(LocalDateTime.now())
                    .createdBy(CAREGIVER_USER_ID).createdAt(LocalDateTime.now()).build();
            when(behavioralIncidentRepository.findById(7L)).thenReturn(Optional.of(inc));

            mockMvc.perform(get("/v1/api/clients/{id}/behavioral-incidents/{incidentId}", CLIENT_ID, 7L)
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }
    }

    // =========================================================
    // POST /{id}/incident-reports
    // =========================================================

    @Nested
    @DisplayName("POST /{id}/incident-reports")
    class CreateIncidentReport {

        private String validBody() {
            return "{\"incident_type\":\"FALL\",\"occurred_at\":\"2026-03-10T09:00:00\"," +
                    "\"location\":\"Bathroom\",\"outcome\":\"No injury\",\"actions_taken\":[\"Applied first aid\"]}";
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 201 with valid payload including actions")
        void validRequest_returns201() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));
            when(incidentReportRepository.save(any(IncidentReport.class)))
                    .thenAnswer(inv -> {
                        IncidentReport r = inv.getArgument(0);
                        r.setId(1L);
                        return r;
                    });

            mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(validBody()))
                    .andExpect(status().isCreated());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("caregiverId and createdBy are always set from session")
        void caregiverFieldsFromSession() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));
            when(incidentReportRepository.save(any(IncidentReport.class)))
                    .thenAnswer(inv -> inv.getArgument(0));

            mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(validBody()))
                    .andExpect(status().isCreated());

            var captor = org.mockito.ArgumentCaptor.forClass(IncidentReport.class);
            verify(incidentReportRepository).save(captor.capture());
            IncidentReport saved = captor.getValue();
            org.assertj.core.api.Assertions.assertThat(saved.getCaregiverId()).isEqualTo(CAREGIVER_ID);
            org.assertj.core.api.Assertions.assertThat(saved.getCreatedBy()).isEqualTo(CAREGIVER_USER_ID);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when incident_type is missing")
        void missingIncidentType_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"occurred_at\":\"2026-03-10T09:00:00\",\"location\":\"Bathroom\",\"outcome\":\"None\"}";
            mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when incident_type is unknown")
        void unknownIncidentType_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"incident_type\":\"INVALID_TYPE\",\"occurred_at\":\"2026-03-10T09:00:00\"," +
                    "\"location\":\"Bathroom\",\"outcome\":\"None\"}";
            mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when occurred_at is missing")
        void missingOccurredAt_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"incident_type\":\"FALL\",\"location\":\"Bathroom\",\"outcome\":\"None\"}";
            mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when location is missing")
        void missingLocation_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"incident_type\":\"FALL\",\"occurred_at\":\"2026-03-10T09:00:00\",\"outcome\":\"None\"}";
            mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when outcome is missing")
        void missingOutcome_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"incident_type\":\"FALL\",\"occurred_at\":\"2026-03-10T09:00:00\",\"location\":\"Bathroom\"}";
            mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("all IncidentType enum values are accepted")
        void allIncidentTypes_accepted() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));
            when(incidentReportRepository.save(any(IncidentReport.class)))
                    .thenAnswer(inv -> inv.getArgument(0));

            String[] types = {"FALL", "BEHAVIORAL_CRISIS", "MEDICAL_EVENT", "ELOPEMENT", "SELF_HARM", "PROPERTY_DAMAGE", "OTHER"};
            for (String type : types) {
                String body = "{\"incident_type\":\"" + type + "\",\"occurred_at\":\"2026-03-10T09:00:00\"," +
                        "\"location\":\"Room\",\"outcome\":\"Resolved\"}";
                mockMvc.perform(post("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                                .with(csrf())
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(body))
                        .andExpect(status().isCreated());
            }
        }
    }

    // =========================================================
    // GET /{id}/incident-reports
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/incident-reports")
    class ListIncidentReports {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with list of reports")
        void returns200WithList() throws Exception {
            stubCaregiverAccess();
            IncidentReport report = IncidentReport.builder()
                    .id(1L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .incidentType(IncidentReport.IncidentType.FALL)
                    .occurredAt(LocalDateTime.now()).location("Kitchen")
                    .outcome("Client uninjured").createdBy(CAREGIVER_USER_ID)
                    .createdAt(LocalDateTime.now()).build();
            when(incidentReportRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(List.of(report));

            mockMvc.perform(get("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(1)))
                    .andExpect(jsonPath("$[0].incidentType").value("FALL"));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with empty list when no reports exist")
        void returns200WithEmptyList() throws Exception {
            stubCaregiverAccess();
            when(incidentReportRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());

            mockMvc.perform(get("/v1/api/clients/{id}/incident-reports", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(0)));
        }
    }

    // =========================================================
    // GET /{id}/incident-reports/{reportId}
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/incident-reports/{reportId}")
    class GetIncidentReport {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 when report exists and belongs to client")
        void found_returns200() throws Exception {
            stubCaregiverAccess();
            IncidentReport report = IncidentReport.builder()
                    .id(3L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .incidentType(IncidentReport.IncidentType.BEHAVIORAL_CRISIS)
                    .occurredAt(LocalDateTime.now()).location("Lounge")
                    .outcome("Situation de-escalated").createdBy(CAREGIVER_USER_ID)
                    .createdAt(LocalDateTime.now()).build();
            when(incidentReportRepository.findById(3L)).thenReturn(Optional.of(report));

            mockMvc.perform(get("/v1/api/clients/{id}/incident-reports/{reportId}", CLIENT_ID, 3L)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(3))
                    .andExpect(jsonPath("$.location").value("Lounge"));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 404 when report does not exist")
        void notFound_returns404() throws Exception {
            stubCaregiverAccess();
            when(incidentReportRepository.findById(404L)).thenReturn(Optional.empty());

            mockMvc.perform(get("/v1/api/clients/{id}/incident-reports/{reportId}", CLIENT_ID, 404L)
                            .with(csrf()))
                    .andExpect(status().isNotFound());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 403 when report belongs to a different client")
        void wrongClient_returns403() throws Exception {
            stubCaregiverAccess();
            IncidentReport report = IncidentReport.builder()
                    .id(8L).clientId(999L)  // different client
                    .caregiverId(CAREGIVER_ID).incidentType(IncidentReport.IncidentType.FALL)
                    .occurredAt(LocalDateTime.now()).location("Hallway")
                    .outcome("Resolved").createdBy(CAREGIVER_USER_ID)
                    .createdAt(LocalDateTime.now()).build();
            when(incidentReportRepository.findById(8L)).thenReturn(Optional.of(report));

            mockMvc.perform(get("/v1/api/clients/{id}/incident-reports/{reportId}", CLIENT_ID, 8L)
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }
    }

    // =========================================================
    // GET /{id}/reports/competency-trends
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/reports/competency-trends")
    class GetCompetencyTrends {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns STABLE with empty lists when no logs exist")
        void noLogs_returnsStable() throws Exception {
            stubCaregiverAccess();
            when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            mockMvc.perform(get("/v1/api/clients/{id}/reports/competency-trends", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("STABLE"))
                    .andExpect(jsonPath("$.weekLabels", hasSize(0)))
                    .andExpect(jsonPath("$.activityTrends", hasSize(0)));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with trends when logs exist")
        void withLogs_returnsTrends() throws Exception {
            stubCaregiverAccess();
            LocalDateTime now = LocalDateTime.now();
            ActivityLog log = ActivityLog.builder()
                    .id(1L).clientId(CLIENT_ID).activityId(100L)
                    .activityName("Bathing").caregiverUserId(CAREGIVER_USER_ID)
                    .competencyScore(4).createdAt(now).build();
            when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(List.of(log));

            mockMvc.perform(get("/v1/api/clients/{id}/reports/competency-trends", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").exists())
                    .andExpect(jsonPath("$.activityTrends", hasSize(1)))
                    .andExpect(jsonPath("$.activityTrends[0].activityName").value("Bathing"));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("accepts optional startDate and endDate query params")
        void withDateRange_returns200() throws Exception {
            stubCaregiverAccess();
            when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            mockMvc.perform(get("/v1/api/clients/{id}/reports/competency-trends", CLIENT_ID)
                            .param("startDate", "2026-01-01")
                            .param("endDate", "2026-03-01")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }
    }

    // =========================================================
    // GET /{id}/reports/behavioral-trends
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/reports/behavioral-trends")
    class GetBehavioralTrends {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns STABLE with empty lists when no incidents exist")
        void noIncidents_returnsStable() throws Exception {
            stubCaregiverAccess();
            when(behavioralIncidentRepository.findByClientIdAndOccurredAtBetweenOrderByOccurredAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            mockMvc.perform(get("/v1/api/clients/{id}/reports/behavioral-trends", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.trend").value("STABLE"))
                    .andExpect(jsonPath("$.weeklyCounts", hasSize(0)))
                    .andExpect(jsonPath("$.topKeywords", hasSize(0)));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns weekly counts and keywords when incidents exist")
        void withIncidents_returnsTrends() throws Exception {
            stubCaregiverAccess();
            LocalDateTime now = LocalDateTime.now();
            BehavioralIncident inc = BehavioralIncident.builder()
                    .id(1L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .observedBehavior("Client was agitated and yelling loudly")
                    .occurredAt(now).createdBy(CAREGIVER_USER_ID).createdAt(now).build();
            when(behavioralIncidentRepository.findByClientIdAndOccurredAtBetweenOrderByOccurredAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(List.of(inc));

            mockMvc.perform(get("/v1/api/clients/{id}/reports/behavioral-trends", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.trend").exists())
                    .andExpect(jsonPath("$.weeklyCounts", hasSize(greaterThan(0))))
                    .andExpect(jsonPath("$.topKeywords").isArray());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("accepts optional startDate and endDate query params")
        void withDateRange_returns200() throws Exception {
            stubCaregiverAccess();
            when(behavioralIncidentRepository.findByClientIdAndOccurredAtBetweenOrderByOccurredAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            mockMvc.perform(get("/v1/api/clients/{id}/reports/behavioral-trends", CLIENT_ID)
                            .param("startDate", "2026-01-01")
                            .param("endDate", "2026-03-01")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }
    }

    // =========================================================
    // GET /{id}/reports/participation
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/reports/participation")
    class GetParticipation {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns STABLE with empty lists when no logs exist")
        void noLogs_returnsStable() throws Exception {
            stubCaregiverAccess();
            when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            mockMvc.perform(get("/v1/api/clients/{id}/reports/participation", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("STABLE"))
                    .andExpect(jsonPath("$.weeklyCounts", hasSize(0)))
                    .andExpect(jsonPath("$.activities", hasSize(0)));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns activity participation breakdown when logs exist")
        void withLogs_returnsParticipation() throws Exception {
            stubCaregiverAccess();
            LocalDateTime recent = LocalDateTime.now().minusDays(1);
            ActivityLog log = ActivityLog.builder()
                    .id(1L).clientId(CLIENT_ID).activityId(50L)
                    .activityName("Meal Preparation").caregiverUserId(CAREGIVER_USER_ID)
                    .competencyScore(3).createdAt(recent).build();
            when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(List.of(log));

            mockMvc.perform(get("/v1/api/clients/{id}/reports/participation", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.activities", hasSize(1)))
                    .andExpect(jsonPath("$.activities[0].activityName").value("Meal Preparation"))
                    .andExpect(jsonPath("$.activities[0].category").value("IADL"));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("ADL activities are categorized correctly")
        void adlActivity_categorizedAsAdl() throws Exception {
            stubCaregiverAccess();
            ActivityLog log = ActivityLog.builder()
                    .id(2L).clientId(CLIENT_ID).activityId(20L)
                    .activityName("Bathing").caregiverUserId(CAREGIVER_USER_ID)
                    .competencyScore(5).createdAt(LocalDateTime.now().minusDays(1)).build();
            when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                    eq(CLIENT_ID), any(), any()))
                    .thenReturn(List.of(log));

            mockMvc.perform(get("/v1/api/clients/{id}/reports/participation", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.activities[0].category").value("ADL"));
        }
    }

    // =========================================================
    // GET /{id}/audit-log
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/audit-log")
    class GetAuditLog {

        private void stubEmptyRepositories() {
            when(activityLogRepository.findByClientIdOrderByCreatedAtDesc(eq(CLIENT_ID), any(Pageable.class)))
                    .thenReturn(Collections.emptyList());
            when(behavioralIncidentRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(incidentReportRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(clientEventRepository.findByClientIdOrderByTappedAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with empty list when no records exist")
        void noRecords_returnsEmpty() throws Exception {
            stubCaregiverAccess();
            stubEmptyRepositories();

            mockMvc.perform(get("/v1/api/clients/{id}/audit-log", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(0)));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns combined audit items from all record types")
        void withRecords_returnsCombinedAudit() throws Exception {
            stubCaregiverAccess();
            LocalDateTime now = LocalDateTime.now();

            ActivityLog log = ActivityLog.builder()
                    .id(1L).clientId(CLIENT_ID).activityId(1L)
                    .activityName("Dressing").caregiverUserId(CAREGIVER_USER_ID)
                    .competencyScore(3).createdAt(now).build();
            BehavioralIncident inc = BehavioralIncident.builder()
                    .id(2L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .observedBehavior("Pacing").occurredAt(now.minusHours(1))
                    .createdBy(CAREGIVER_USER_ID).createdAt(now.minusHours(1)).build();

            when(activityLogRepository.findByClientIdOrderByCreatedAtDesc(eq(CLIENT_ID), any(Pageable.class)))
                    .thenReturn(List.of(log));
            when(behavioralIncidentRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(List.of(inc));
            when(incidentReportRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(clientEventRepository.findByClientIdOrderByTappedAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(userRepository.findAllById(any())).thenReturn(List.of(caregiverUser));

            mockMvc.perform(get("/v1/api/clients/{id}/audit-log", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(2)));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("type=ACTIVITY_LOG filter returns only activity log items")
        void typeFilter_activityLog() throws Exception {
            stubCaregiverAccess();
            LocalDateTime now = LocalDateTime.now();

            ActivityLog log = ActivityLog.builder()
                    .id(1L).clientId(CLIENT_ID).activityId(1L)
                    .activityName("Eating").caregiverUserId(CAREGIVER_USER_ID)
                    .competencyScore(4).createdAt(now).build();

            when(activityLogRepository.findByClientIdOrderByCreatedAtDesc(eq(CLIENT_ID), any(Pageable.class)))
                    .thenReturn(List.of(log));
            when(behavioralIncidentRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(incidentReportRepository.findByClientIdOrderByOccurredAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(clientEventRepository.findByClientIdOrderByTappedAtDesc(CLIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(userRepository.findAllById(any())).thenReturn(List.of(caregiverUser));

            mockMvc.perform(get("/v1/api/clients/{id}/audit-log", CLIENT_ID)
                            .param("type", "ACTIVITY_LOG")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(1)))
                    .andExpect(jsonPath("$[0].type").value("ACTIVITY_LOG"));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("date range filter excludes items outside range")
        void dateRangeFilter_excludesOutsideItems() throws Exception {
            stubCaregiverAccess();
            stubEmptyRepositories();

            mockMvc.perform(get("/v1/api/clients/{id}/audit-log", CLIENT_ID)
                            .param("startDate", "2026-03-01")
                            .param("endDate", "2026-03-10")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(0)));
        }
    }

    // =========================================================
    // POST /{id}/events
    // =========================================================

    @Nested
    @DisplayName("POST /{id}/events")
    class CreateClientEvent {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 201 with valid activity_id")
        void validRequest_returns201() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));
            when(clientEventRepository.save(any(ClientEvent.class)))
                    .thenAnswer(inv -> {
                        ClientEvent e = inv.getArgument(0);
                        e.setId(1L);
                        return e;
                    });

            String body = "{\"activity_id\": 5}";
            mockMvc.perform(post("/v1/api/clients/{id}/events", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isCreated());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when activity_id is missing")
        void missingActivityId_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{}";
            mockMvc.perform(post("/v1/api/clients/{id}/events", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 400 when activity_id is not a number")
        void invalidActivityId_returns400() throws Exception {
            stubCaregiverAccess();
            when(caregiverRepository.findByUserId(CAREGIVER_USER_ID)).thenReturn(Optional.of(caregiver));

            String body = "{\"activity_id\": \"not-a-number\"}";
            mockMvc.perform(post("/v1/api/clients/{id}/events", CLIENT_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }
    }

    // =========================================================
    // GET /{id}/events
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/events")
    class ListClientEvents {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with list of client events")
        void returns200WithList() throws Exception {
            stubCaregiverAccess();
            ClientEvent event = ClientEvent.builder()
                    .id(1L).clientId(CLIENT_ID).caregiverId(CAREGIVER_ID)
                    .activityId(7L).tappedAt(LocalDateTime.now())
                    .createdBy(CAREGIVER_USER_ID).createdAt(LocalDateTime.now()).build();
            when(clientEventRepository.findByClientIdOrderByTappedAtDesc(CLIENT_ID))
                    .thenReturn(List.of(event));

            mockMvc.perform(get("/v1/api/clients/{id}/events", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(1)))
                    .andExpect(jsonPath("$[0].activityId").value(7));
        }
    }

    // =========================================================
    // GET /{id}/activities
    // =========================================================

    @Nested
    @DisplayName("GET /{id}/activities")
    class GetClientActivities {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("returns 200 with empty list (stub)")
        void returns200EmptyList() throws Exception {
            stubCaregiverAccess();

            mockMvc.perform(get("/v1/api/clients/{id}/activities", CLIENT_ID)
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$", hasSize(0)));
        }
    }
}
