package com.careconnect.controller;

import com.careconnect.dto.ConnectionRequestSummary;
import com.careconnect.model.ConnectionRequest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.ConnectionRequestService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Instant;
import java.util.List;

import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class ConnectionRequestControllerTest {

    private MockMvc mockMvc;

    @Mock
    private ConnectionRequestService connectionRequestService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private ConnectionRequestController controller;

    private User caregiver;
    private User patient;

    private static User user(long id, Role role, String name) {
        final User u = new User();
        u.setId(id);
        u.setRole(role);
        u.setName(name);
        u.setEmail(name.toLowerCase().replace(' ', '.') + "@example.com");
        u.setPasswordHash("$2a$10$secret-hash");
        return u;
    }

    private ConnectionRequest pending() {
        return ConnectionRequest.builder()
                .id(100L)
                .caregiver(caregiver)
                .patient(patient)
                .status("PENDING")
                .relationshipType("Caregiver")
                .message("Hello")
                .requestedAt(Instant.parse("2026-10-18T12:00:00Z"))
                .token("secret-token")
                .build();
    }

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
        lenient().when(connectionRequestService.toSummary(any())).thenAnswer(inv -> {
            final ConnectionRequest r = inv.getArgument(0);
            return ConnectionRequestSummary.from(r, r.getCaregiver().getName(), r.getPatient().getName());
        });
        caregiver = user(10L, Role.CAREGIVER, "Carey Tester");
        patient = user(9L, Role.PATIENT, "Index Tester");
    }

    @Test
    void create_usesTheCallerNotTheBodyCaregiverId() throws Exception {
        // Arrange: the body names caregiver 1, the caller is caregiver user 10
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        final ConnectionRequest saved = pending();
        when(connectionRequestService.createRequest(eq(10L), eq("index.tester@example.com"), eq("Caregiver"), eq("Hello")))
                .thenReturn(saved);

        // Act / Assert
        mockMvc.perform(post("/v1/api/connection-requests/create")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"caregiverId": 1, "patientEmail": "index.tester@example.com",
                                 "relationshipType": "Caregiver", "message": "Hello"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.requestId").value(100));
        verify(connectionRequestService, never()).createRequest(eq(1L), any(), any(), any());
    }

    @Test
    void create_rejectedRequestReturnsBadRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        when(connectionRequestService.createRequest(eq(10L), any(), any(), any()))
                .thenThrow(new IllegalStateException("You are already connected to this patient"));

        mockMvc.perform(post("/v1/api/connection-requests/create")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"patientEmail\": \"index.tester@example.com\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("You are already connected to this patient"));
    }

    @Test
    void incoming_returnsSummariesWithoutTokenOrCredentials() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(connectionRequestService.getPendingRequestsForPatient(patient)).thenReturn(List.of(pending()));

        mockMvc.perform(get("/v1/api/connection-requests/incoming"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(100))
                .andExpect(jsonPath("$[0].caregiverName").value("Carey Tester"))
                .andExpect(jsonPath("$[0].status").value("PENDING"))
                .andExpect(content().string(not(containsString("secret-token"))))
                .andExpect(content().string(not(containsString("secret-hash"))));
    }

    @Test
    void incoming_forbiddenForNonPatients() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);

        mockMvc.perform(get("/v1/api/connection-requests/incoming"))
                .andExpect(status().isForbidden());
    }

    @Test
    void outgoing_returnsTheCallersPendingRequests() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        when(connectionRequestService.getPendingRequestsByCaregiver(caregiver)).thenReturn(List.of(pending()));

        mockMvc.perform(get("/v1/api/connection-requests/outgoing"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].patientName").value("Index Tester"));
    }

    @Test
    void outgoing_forbiddenForNonCaregivers() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);

        mockMvc.perform(get("/v1/api/connection-requests/outgoing"))
                .andExpect(status().isForbidden());
    }

    @Test
    void accept_recordsThePatientsAcceptance() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);

        mockMvc.perform(post("/v1/api/connection-requests/100/accept"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Connection request accepted successfully"));
        verify(connectionRequestService).respond(100L, patient, true);
    }

    @Test
    void reject_recordsThePatientsRejection() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);

        mockMvc.perform(post("/v1/api/connection-requests/100/reject"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Connection request rejected successfully"));
        verify(connectionRequestService).respond(100L, patient, false);
    }

    @Test
    void accept_forbiddenForCaregivers() throws Exception {
        // A caregiver cannot approve their own request
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);

        mockMvc.perform(post("/v1/api/connection-requests/100/accept"))
                .andExpect(status().isForbidden());
        verify(connectionRequestService, never()).respond(any(), any(), anyBoolean());
    }

    @Test
    void accept_someoneElsesRequestIsNotFound() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        doThrow(new IllegalArgumentException("Connection request not found"))
                .when(connectionRequestService).respond(100L, patient, true);

        mockMvc.perform(post("/v1/api/connection-requests/100/accept"))
                .andExpect(status().isNotFound());
    }

    @Test
    void accept_alreadyAnsweredIsConflict() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        doThrow(new IllegalStateException("This request has already been processed"))
                .when(connectionRequestService).respond(100L, patient, true);

        mockMvc.perform(post("/v1/api/connection-requests/100/accept"))
                .andExpect(status().isConflict());
    }
}
