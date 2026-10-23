package com.careconnect.service;

import com.careconnect.model.Caregiver;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.Patient;
import com.careconnect.model.ConnectionRequest;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ConnectionRequestRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
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
    private CaregiverRepository caregiverRepo;

    @Mock
    private PatientRepository patientRepo;

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
        // remaining @Autowired field-injected dependencies, so notificationService is
        // set via reflection.
        ReflectionTestUtils.setField(connectionRequestService, "notificationService", notificationService);

        caregiver = new User();
        caregiver.setId(1L);
        caregiver.setName("Jane Caregiver");
        caregiver.setEmail("jane@example.com");
        caregiver.setRole(Role.CAREGIVER);

        patient = new User();
        patient.setId(2L);
        patient.setName("John Patient");
        patient.setEmail("john@example.com");
        patient.setRole(Role.PATIENT);

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
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
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
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
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
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
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

        assertEquals("Only caregivers can send connection requests", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - patient not found by email - throws IllegalArgumentException")
    void createRequest_patientNotFound_throwsIllegalArgumentException() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmailAndRole("unknown@example.com", Role.PATIENT)).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.createRequest(1L, "unknown@example.com", "Family", "msg"));

        assertEquals("Patient not found with email: unknown@example.com", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - pending request already exists - throws IllegalStateException")
    void createRequest_pendingRequestAlreadyExists_throwsIllegalStateException() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")).thenReturn(true);

        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> connectionRequestService.createRequest(1L, "john@example.com", "Family", "msg"));

        assertEquals("There's already a pending connection request to this patient", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - caller is not a caregiver - throws and saves nothing")
    void createRequest_callerNotCaregiver_throws() throws Exception {
        when(userRepo.findById(2L)).thenReturn(Optional.of(patient));

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.createRequest(2L, "jane@example.com", "Family", "msg"));

        assertEquals("Only caregivers can send connection requests", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - already connected - throws IllegalStateException")
    void createRequest_alreadyConnected_throwsIllegalStateException() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
        when(linkRepo.existsByCaregiverUserAndPatientUserAndStatus(
                caregiver, patient, CaregiverPatientLink.LinkStatus.ACTIVE)).thenReturn(true);

        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> connectionRequestService.createRequest(1L, "john@example.com", "Family", "msg"));

        assertEquals("You are already connected to this patient", ex.getMessage());
        verify(connectionRequestRepo, never()).save(any());
    }

    @Test
    @DisplayName("createRequest - email tells the patient to respond in the app and carries no token")
    void createRequest_emailHasNoTokenLink() throws Exception {
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        final ConnectionRequest request =
                connectionRequestService.createRequest(1L, "john@example.com", "Family", "msg");

        final ArgumentCaptor<String> body = ArgumentCaptor.forClass(String.class);
        verify(emailService).sendHtmlEmail(eq("john@example.com"), anyString(), body.capture(), eq("html"));
        assertTrue(body.getValue().contains("accept or decline this request from your dashboard"));
        assertFalse(body.getValue().contains(request.getToken()));
    }

    @Test
    @DisplayName("createRequest - notification service is null - request still created successfully")
    void createRequest_notificationServiceIsNull_requestStillCreated() throws Exception {
        // Set notificationService to null to cover the null-guard branch
        ReflectionTestUtils.setField(connectionRequestService, "notificationService", null);

        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
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
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
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
    // respond tests
    // ========================================================================

    @Test
    @DisplayName("respond - accepted with notification service - creates link and sends notifications")
    void respond_accepted_createsLinkAndSendsNotifications() throws Exception {
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.respond(100L, patient, true);

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
    @DisplayName("respond - rejected - sets status and sends email without creating link")
    void respond_rejected_setsStatusAndSendsEmailWithoutLink() throws Exception {
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.respond(100L, patient, false);

        assertEquals("REJECTED", pendingRequest.getStatus());
        assertNotNull(pendingRequest.getRespondedAt());

        verify(connectionRequestRepo).save(pendingRequest);
        verify(linkRepo, never()).save(any());
        verify(notificationService, never()).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
        verify(emailService).sendHtmlEmail(eq("jane@example.com"), contains("Declined"), anyString(), eq("html"));
    }

    @Test
    @DisplayName("respond - unknown request - throws IllegalArgumentException")
    void respond_unknownRequest_throwsIllegalArgumentException() throws Exception {
        when(connectionRequestRepo.findById(404L)).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.respond(404L, patient, true));

        assertEquals("Connection request not found", ex.getMessage());
    }

    @Test
    @DisplayName("respond - another patient's request - reported as not found and nothing changes")
    void respond_anotherPatientsRequest_reportedAsNotFound() throws Exception {
        // Arrange
        final User otherPatient = new User();
        otherPatient.setId(3L);
        otherPatient.setRole(Role.PATIENT);
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));

        // Act
        final IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> connectionRequestService.respond(100L, otherPatient, true));

        // Assert
        assertEquals("Connection request not found", ex.getMessage());
        assertEquals("PENDING", pendingRequest.getStatus());
        verify(linkRepo, never()).save(any());
    }

    @Test
    @DisplayName("respond - accepted when already linked - does not create a second link")
    void respond_acceptedWhenAlreadyLinked_doesNotDuplicateLink() throws Exception {
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));
        when(linkRepo.existsByCaregiverUserAndPatientUserAndStatus(
                caregiver, patient, CaregiverPatientLink.LinkStatus.ACTIVE)).thenReturn(true);

        connectionRequestService.respond(100L, patient, true);

        assertEquals("ACCEPTED", pendingRequest.getStatus());
        verify(linkRepo, never()).save(any());
    }

    @Test
    @DisplayName("respond - request already accepted - throws IllegalStateException")
    void respond_requestAlreadyAccepted_throwsIllegalStateException() throws Exception {
        pendingRequest.setStatus("ACCEPTED");
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));

        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> connectionRequestService.respond(100L, patient, true));

        assertEquals("This request has already been processed", ex.getMessage());
    }

    @Test
    @DisplayName("respond - request already rejected - throws IllegalStateException")
    void respond_requestAlreadyRejected_throwsIllegalStateException() throws Exception {
        pendingRequest.setStatus("REJECTED");
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));

        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> connectionRequestService.respond(100L, patient, false));

        assertEquals("This request has already been processed", ex.getMessage());
    }

    @Test
    @DisplayName("respond - accepted with null notification service - creates link without notification failure")
    void respond_acceptedWithNullNotificationService_createsLinkSuccessfully() throws Exception {
        // Set notificationService to null to cover the null-guard branch in respond
        ReflectionTestUtils.setField(connectionRequestService, "notificationService", null);

        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.respond(100L, patient, true);

        assertEquals("ACCEPTED", pendingRequest.getStatus());
        verify(linkRepo).save(any(CaregiverPatientLink.class));
        verify(notificationService, never()).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
        verify(emailService).sendHtmlEmail(eq("jane@example.com"), contains("Accepted"), anyString(), eq("html"));
    }

    @Test
    @DisplayName("respond - accepted but notification throws exception - still completes successfully")
    void respond_acceptedNotificationThrows_stillCompletesSuccessfully() throws Exception {
        // notificationService is injected via setUp, so the code will actually call it and hit the catch
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));
        when(notificationService.sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap()))
                .thenThrow(new RuntimeException("Firebase down"));

        connectionRequestService.respond(100L, patient, true);

        assertEquals("ACCEPTED", pendingRequest.getStatus());
        verify(linkRepo).save(any(CaregiverPatientLink.class));
        // Verify notification was attempted (and failed gracefully)
        verify(notificationService).sendNotificationToUser(anyLong(), anyString(), anyString(), anyString(), anyMap());
        verify(emailService).sendHtmlEmail(eq("jane@example.com"), anyString(), anyString(), eq("html"));
    }

    @Test
    @DisplayName("respond - accepted with null relationshipType - uses 'Caregiver' default in notification data")
    void respond_acceptedWithNullRelationshipType_usesDefaultInNotification() throws Exception {
        pendingRequest.setRelationshipType(null);
        when(connectionRequestRepo.findById(100L)).thenReturn(Optional.of(pendingRequest));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.respond(100L, patient, true);

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
        when(connectionRequestRepo.findByPatientAndStatus(patient, "PENDING"))
                .thenReturn(List.of(pendingRequest));

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsForPatient(patient);

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals(pendingRequest, result.get(0));
    }

    @Test
    @DisplayName("getPendingRequestsForPatient - valid patient with no pending requests - returns empty list")
    void getPendingRequestsForPatient_validPatientNoPending_returnsEmptyList() throws Exception {
        when(connectionRequestRepo.findByPatientAndStatus(patient, "PENDING"))
                .thenReturn(List.of());

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsForPatient(patient);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    // ========================================================================
    // getPendingRequestsByCaregiver tests
    // ========================================================================

    @Test
    @DisplayName("getPendingRequestsByCaregiver - valid caregiver - returns pending requests")
    void getPendingRequestsByCaregiver_validCaregiver_returnsPendingRequests() throws Exception {
        when(connectionRequestRepo.findByCaregiverAndStatus(caregiver, "PENDING"))
                .thenReturn(List.of(pendingRequest));

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsByCaregiver(caregiver);

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals(pendingRequest, result.get(0));
    }

    @Test
    @DisplayName("getPendingRequestsByCaregiver - valid caregiver with no pending requests - returns empty list")
    void getPendingRequestsByCaregiver_validCaregiverNoPending_returnsEmptyList() throws Exception {
        when(connectionRequestRepo.findByCaregiverAndStatus(caregiver, "PENDING"))
                .thenReturn(List.of());

        final List<ConnectionRequest> result = connectionRequestService.getPendingRequestsByCaregiver(caregiver);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    // ========================================================================
    // display names
    // ========================================================================

    @Test
    @DisplayName("displayName - uses users.name when set")
    void displayName_usesUserName() {
        assertEquals("Jane Caregiver", connectionRequestService.displayName(caregiver));
        verifyNoInteractions(caregiverRepo, patientRepo);
    }

    @Test
    @DisplayName("displayName - seeded caregiver without users.name uses the caregiver profile")
    void displayName_caregiverWithoutName_usesProfile() {
        // Arrange: seeded accounts carry their name only on the profile
        caregiver.setName(null);
        final Caregiver profile = new Caregiver();
        profile.setFirstName("Cara");
        profile.setLastName("Giver");
        when(caregiverRepo.findByUser(caregiver)).thenReturn(Optional.of(profile));

        // Act / Assert
        assertEquals("Cara Giver", connectionRequestService.displayName(caregiver));
    }

    @Test
    @DisplayName("displayName - patient without users.name uses the patient profile")
    void displayName_patientWithoutName_usesProfile() {
        patient.setName("  ");
        when(patientRepo.findByUser(patient))
                .thenReturn(Optional.of(Patient.builder().firstName("Mary").lastName("Johnson").build()));

        assertEquals("Mary Johnson", connectionRequestService.displayName(patient));
    }

    @Test
    @DisplayName("displayName - no name anywhere falls back to the email")
    void displayName_noNameAnywhere_usesEmail() {
        caregiver.setName(null);
        when(caregiverRepo.findByUser(caregiver)).thenReturn(Optional.empty());

        assertEquals("jane@example.com", connectionRequestService.displayName(caregiver));
    }

    @Test
    @DisplayName("toSummary - resolves both names and carries no token")
    void toSummary_resolvesNames() {
        caregiver.setName(null);
        final Caregiver profile = new Caregiver();
        profile.setFirstName("Cara");
        profile.setLastName("Giver");
        when(caregiverRepo.findByUser(caregiver)).thenReturn(Optional.of(profile));

        final var summary = connectionRequestService.toSummary(pendingRequest);

        assertEquals("Cara Giver", summary.caregiverName());
        assertEquals("John Patient", summary.patientName());
        assertEquals(100L, summary.id());
    }

    @Test
    @DisplayName("createRequest - notification names a caregiver who has no users.name")
    void createRequest_notificationUsesProfileName() throws Exception {
        caregiver.setName(null);
        final Caregiver profile = new Caregiver();
        profile.setFirstName("Cara");
        profile.setLastName("Giver");
        when(caregiverRepo.findByUser(caregiver)).thenReturn(Optional.of(profile));
        when(userRepo.findById(1L)).thenReturn(Optional.of(caregiver));
        when(userRepo.findByEmailAndRole("john@example.com", Role.PATIENT)).thenReturn(Optional.of(patient));
        when(connectionRequestRepo.save(any(ConnectionRequest.class))).thenAnswer(inv -> inv.getArgument(0));

        connectionRequestService.createRequest(1L, "john@example.com", "Family", "msg");

        verify(notificationService).sendNotificationToUser(
                eq(2L), anyString(), eq("Cara Giver would like to connect with you as your caregiver"),
                eq("CONNECTION_REQUEST"), anyMap());
    }
}
