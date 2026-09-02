package com.careconnect.service;

import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.ConnectionRequest;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ConnectionRequestRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class ConnectionRequestServiceTest {

    @Mock
    private ConnectionRequestRepository connectionRequestRepo;

    @Mock
    private UserRepository userRepo;

    @Mock
    private CaregiverPatientLinkRepository linkRepo;

    @Mock
    private EmailService emailService;

    @Mock
    private NotificationService notificationService;

    @InjectMocks
    private ConnectionRequestService connectionRequestService;

    private User caregiver;
    private User patient;
    private ConnectionRequest pendingRequest;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        // Mockito 5's @InjectMocks uses constructor injection and does NOT inject
        // remaining @Autowired field-injected dependencies. We must manually inject
        // notificationService and the @Value frontendBaseUrl via reflection.
        ReflectionTestUtils.setField(connectionRequestService, "notificationService", notificationService);
        ReflectionTestUtils.setField(connectionRequestService, "frontendBaseUrl", "http://localhost:3000");

        caregiver = new User();
        caregiver.setId(1L);
        caregiver.setName("Jane Caregiver");
        caregiver.setEmail("jane@example.com");

        patient = new User();
        patient.setId(2L);
        patient.setName("John Patient");
        patient.setEmail("john@example.com");

        pendingRequest = ConnectionRequest.builder()
                .id(100L)
                .caregiver(caregiver)
                .patient(patient)
                .status("PENDING")
                .relationshipType("Family")
                .message("I would like to help.")
                .requestedAt(Instant.now())
                .token("test-token-123")
                .build();
    }

    // ========================================================================
    // createRequest tests
    // ========================================================================

    @Test
    @DisplayName("createRequest - valid inputs with message and notification service - returns saved request and sends notification")
    void createRequest_validInputsWithMessageAndNotification_returnsSavedRequest() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmail("john@example.com")).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")).thenReturn(false);
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        final ConnectionRequest result = connectionRequestService.createRequest(1L, "john@example.com", "Family", "Please connect.");

        assertNotNull(result);
        assertEquals("PENDING", result.getStatus());
        assertEquals(caregiver, result.getCaregiver());
        assertEquals(patient, result.getPatient());
        assertEquals("Family", result.getRelationshipType());
        assertEquals("Please connect.", result.getMessage());
        assertNotNull(result.getToken());
        assertNotNull(result.getRequestedAt());

        verify(connectionRequestRepo).save(any(ConnectionRequest.class));
        verify(emailService).sendHtmlEmail(eq("john@example.com"), anyString(), anyString(), eq("html"));
        // notificationService IS injected via ReflectionTestUtils, so notification is sent
        verify(notificationService).sendNotificationToUser(
                eq(2L), anyString(), anyString(), eq("CONNECTION_REQUEST"), anyMap());
    }

    @Test
    @DisplayName("createRequest - valid inputs with null message - returns saved request with null message in email")
    void createRequest_validInputsWithNullMessage_returnsSavedRequest() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmail("john@example.com")).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")).thenReturn(false);
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        final ConnectionRequest result = connectionRequestService.createRequest(1L, "john@example.com", "Family", null);

        assertNotNull(result);
        assertNull(result.getMessage());
        verify(emailService).sendHtmlEmail(eq("john@example.com"), anyString(), anyString(), eq("html"));
    }

    @Test
    @DisplayName("createRequest - valid inputs with empty message - returns saved request with empty message in email")
    void createRequest_validInputsWithEmptyMessage_returnsSavedRequest() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmail("john@example.com")).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")).thenReturn(false);
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        final ConnectionRequest result = connectionRequestService.createRequest(1L, "john@example.com", "Family", "");

        assertNotNull(result);
        assertEquals("", result.getMessage());
        verify(emailService).sendHtmlEmail(eq("john@example.com"), anyString(), anyString(), eq("html"));
    }

    @Test
    @DisplayName("createRequest - caregiver not found - throws IllegalArgumentException")
    void createRequest_caregiverNotFound_throwsIllegalArgumentException() throws Exception {
        when(userRepo.findById(99L)).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.createRequest(99L, "john@example.com", "Family", "msg"));

        assertEquals("Caregiver not found", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - patient not found by email - throws IllegalArgumentException")
    void createRequest_patientNotFound_throwsIllegalArgumentException() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmail("unknown@example.com")).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.createRequest(1L, "unknown@example.com", "Family", "msg"));

        assertEquals("Patient not found with email: unknown@example.com", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - pending request already exists - throws IllegalStateException")
    void createRequest_pendingRequestAlreadyExists_throwsIllegalStateException() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmail("john@example.com")).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")).thenReturn(true);

        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> connectionRequestService.createRequest(1L, "john@example.com", "Family", "msg"));

        assertEquals("There's already a pending connection request to this patient", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - notification service is null - request still created successfully")
    void createRequest_notificationServiceIsNull_requestStillCreated() throws Exception {
        // Set notificationService to null to cover the null-guard branch
        ReflectionTestUtils.setField(connectionRequestService, "notificationService", null);

        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmail("john@example.com")).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")).thenReturn(false);
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        final ConnectionRequest result = connectionRequestService.createRequest(1L, "john@example.com", "Family", "msg");

        assertNotNull(result);
        verify(connectionRequestRepo).save(any(ConnectionRequest.class));
        verify(emailService).sendHtmlEmail(eq("john@example.com"), anyString(), anyString(), eq("html"));
        // notificationService is null so it should not be invoked
        verify(notificationService, never()).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
    }

    @Test
    @DisplayName("createRequest - notification service throws exception - request still created successfully")
    void createRequest_notificationServiceThrowsException_requestStillCreated() throws Exception {
        // notificationService is injected via setUp, so the code will actually call it
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmail("john@example.com")).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")).thenReturn(false);
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));
        when(notificationService.sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap()))
                .thenThrow(new RuntimeException("Firebase unavailable"));

        final ConnectionRequest result = connectionRequestService.createRequest(1L, "john@example.com", "Family", "msg");

        assertNotNull(result);
        assertEquals("PENDING", result.getStatus());
        verify(connectionRequestRepo).save(any(ConnectionRequest.class));
        // Verify notification was attempted (and failed gracefully)
        verify(notificationService).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
    }

    // ========================================================================
    // processResponse tests
    // ========================================================================

    @Test
    @DisplayName("processResponse - accepted with notification service - creates link and sends notifications")
    void processResponse_accepted_createsLinkAndSendsNotifications() throws Exception {
        when(connectionRequestRepo.findByToken("test-token-123")).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.processResponse("test-token-123", true);

        assertEquals("ACCEPTED", pendingRequest.getStatus());
        assertNotNull(pendingRequest.getRespondedAt());

        verify(connectionRequestRepo).save(pendingRequest);

        // Verify caregiver-patient link creation
        final ArgumentCaptor<CaregiverPatientLink> linkCaptor = ArgumentCaptor.forClass(CaregiverPatientLink.class);
        verify(linkRepo).save(linkCaptor.capture());
        final CaregiverPatientLink savedLink = linkCaptor.getValue();
        assertEquals(caregiver, savedLink.getCaregiverUser());
        assertEquals(patient, savedLink.getPatientUser());
        assertEquals(caregiver, savedLink.getCreatedBy());
        assertEquals(CaregiverPatientLink.LinkType.PERMANENT, savedLink.getLinkType());
        assertEquals(CaregiverPatientLink.LinkStatus.ACTIVE, savedLink.getStatus());
        assertEquals("Family", savedLink.getNotes());

        // notificationService IS injected via ReflectionTestUtils, so notification is sent
        verify(notificationService).sendNotificationToUser(
                eq(1L), anyString(), anyString(), eq("CONNECTION_ACCEPTED"), anyMap());

        // Verify response email sent to caregiver
        verify(emailService).sendHtmlEmail(eq("jane@example.com"), contains("Accepted"), anyString(), eq("html"));
    }

    @Test
    @DisplayName("processResponse - rejected - sets status and sends email without creating link")
    void processResponse_rejected_setsStatusAndSendsEmailWithoutLink() throws Exception {
        when(connectionRequestRepo.findByToken("test-token-123")).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.processResponse("test-token-123", false);

        assertEquals("REJECTED", pendingRequest.getStatus());
        assertNotNull(pendingRequest.getRespondedAt());

        verify(connectionRequestRepo).save(pendingRequest);
        verify(linkRepo, never()).save(any());
        verify(notificationService, never()).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
        verify(emailService).sendHtmlEmail(eq("jane@example.com"), contains("Declined"), anyString(), eq("html"));
    }

    @Test
    @DisplayName("processResponse - invalid token - throws IllegalArgumentException")
    void processResponse_invalidToken_throwsIllegalArgumentException() throws Exception {
        when(connectionRequestRepo.findByToken("bad-token")).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.processResponse("bad-token", true));

        assertEquals("Invalid request token", ex.getMessage());
    }

    @Test
    @DisplayName("processResponse - request already accepted - throws IllegalStateException")
    void processResponse_requestAlreadyAccepted_throwsIllegalStateException() throws Exception {
        pendingRequest.setStatus("ACCEPTED");
        when(connectionRequestRepo.findByToken("test-token-123")).thenReturn(Optional.of(pendingRequest));

        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> connectionRequestService.processResponse("test-token-123", true));

        assertEquals("This request has already been processed", ex.getMessage());
    }

    @Test
    @DisplayName("processResponse - request already rejected - throws IllegalStateException")
    void processResponse_requestAlreadyRejected_throwsIllegalStateException() throws Exception {
        pendingRequest.setStatus("REJECTED");
        when(connectionRequestRepo.findByToken("test-token-123")).thenReturn(Optional.of(pendingRequest));

        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> connectionRequestService.processResponse("test-token-123", false));

        assertEquals("This request has already been processed", ex.getMessage());
    }

    @Test
    @DisplayName("processResponse - accepted with null notification service - creates link without notification failure")
    void processResponse_acceptedWithNullNotificationService_createsLinkSuccessfully() throws Exception {
        // Set notificationService to null to cover the null-guard branch in processResponse
        ReflectionTestUtils.setField(connectionRequestService, "notificationService", null);

        when(connectionRequestRepo.findByToken("test-token-123")).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.processResponse("test-token-123", true);

        assertEquals("ACCEPTED", pendingRequest.getStatus());
        verify(linkRepo).save(any(CaregiverPatientLink.class));
        verify(notificationService, never()).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
        verify(emailService).sendHtmlEmail(eq("jane@example.com"), contains("Accepted"), anyString(), eq("html"));
    }

    @Test
    @DisplayName("processResponse - accepted but notification throws exception - still completes successfully")
    void processResponse_acceptedNotificationThrows_stillCompletesSuccessfully() throws Exception {
        // notificationService is injected via setUp, so the code will actually call it and hit the catch
        when(connectionRequestRepo.findByToken("test-token-123")).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));
        when(notificationService.sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap()))
                .thenThrow(new RuntimeException("Firebase down"));

        connectionRequestService.processResponse("test-token-123", true);

        assertEquals("ACCEPTED", pendingRequest.getStatus());
        verify(linkRepo).save(any(CaregiverPatientLink.class));
        // Verify notification was attempted (and failed gracefully)
        verify(notificationService).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
        verify(emailService).sendHtmlEmail(eq("jane@example.com"), anyString(), anyString(), eq("html"));
    }

    @Test
    @DisplayName("processResponse - accepted with null relationshipType - uses 'Caregiver' default in notification data")
    void processResponse_acceptedWithNullRelationshipType_usesDefaultInNotification() throws Exception {
        pendingRequest.setRelationshipType(null);
        when(connectionRequestRepo.findByToken("test-token-123")).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.processResponse("test-token-123", true);

        assertEquals("ACCEPTED", pendingRequest.getStatus());
        verify(linkRepo).save(any(CaregiverPatientLink.class));

        // notificationService IS injected, so notification is sent with default "Caregiver"
        @SuppressWarnings("unchecked") final ArgumentCaptor<Map<String, String>> dataCaptor = ArgumentCaptor.forClass(Map.class);
        verify(notificationService).sendNotificationToUser(
                eq(1L), anyString(), anyString(), eq("CONNECTION_ACCEPTED"), dataCaptor.capture());
        final Map<String, String> capturedData = dataCaptor.getValue();
        assertEquals("Caregiver", capturedData.get("relationshipType"));

        verify(emailService).sendHtmlEmail(eq("jane@example.com"), anyString(), anyString(), eq("html"));
    }

    // ========================================================================
    // getPendingRequestsForPatient tests
    // ========================================================================

    @Test
    @DisplayName("getPendingRequestsForPatient - valid patient - returns pending requests")
    void getPendingRequestsForPatient_validPatient_returnsPendingRequests() throws Exception {
        when(userRepo.findById(2L)).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.findByPatientAndStatus(patient, "PENDING"))
                .thenReturn(List.of(pendingRequest));

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsForPatient(2L);

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals(pendingRequest, result.get(0));
    }

    @Test
    @DisplayName("getPendingRequestsForPatient - valid patient with no pending requests - returns empty list")
    void getPendingRequestsForPatient_validPatientNoPending_returnsEmptyList() throws Exception {
        when(userRepo.findById(2L)).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.findByPatientAndStatus(patient, "PENDING"))
                .thenReturn(List.of());

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsForPatient(2L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPendingRequestsForPatient - patient not found - throws IllegalArgumentException")
    void getPendingRequestsForPatient_patientNotFound_throwsIllegalArgumentException() throws Exception {
        when(userRepo.findById(99L)).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.getPendingRequestsForPatient(99L));

        assertEquals("Patient not found", ex.getMessage());
    }

    // ========================================================================
    // getPendingRequestsByCaregiver tests
    // ========================================================================

    @Test
    @DisplayName("getPendingRequestsByCaregiver - valid caregiver - returns pending requests")
    void getPendingRequestsByCaregiver_validCaregiver_returnsPendingRequests() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(connectionRequestRepo.findByCaregiverAndStatus(caregiver, "PENDING"))
                .thenReturn(List.of(pendingRequest));

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsByCaregiver(1L);

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals(pendingRequest, result.get(0));
    }

    @Test
    @DisplayName("getPendingRequestsByCaregiver - valid caregiver with no pending requests - returns empty list")
    void getPendingRequestsByCaregiver_validCaregiverNoPending_returnsEmptyList() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(connectionRequestRepo.findByCaregiverAndStatus(caregiver, "PENDING"))
                .thenReturn(List.of());

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsByCaregiver(1L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPendingRequestsByCaregiver - caregiver not found - throws IllegalArgumentException")
    void getPendingRequestsByCaregiver_caregiverNotFound_throwsIllegalArgumentException() throws Exception {
        when(userRepo.findById(99L)).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.getPendingRequestsByCaregiver(99L));

        assertEquals("Caregiver not found", ex.getMessage());
    }
}
