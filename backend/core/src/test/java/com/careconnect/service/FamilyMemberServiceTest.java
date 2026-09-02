package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.model.*;
import com.careconnect.model.User;
import com.careconnect.repository.*;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.*;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDateTime;
import java.time.Period;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class FamilyMemberServiceTest {

    @Mock
    private FamilyMemberRepository familyMemberRepository;
    @Mock
    private FamilyMemberLinkRepository familyMemberLinkRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private PasswordEncoder passwordEncoder;
    @Mock
    private EmailService emailService;
    @Mock
    private AnalyticsService analyticsService;
    @Mock
    private GamificationService gamificationService;

    @InjectMocks
    private FamilyMemberService familyMemberService;

    private User patientUser;
    private User familyUser;
    private User grantedByUser;
    private Patient patient;
    private FamilyMember familyMember;
    private FamilyMemberLink link;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        familyMemberService = new FamilyMemberService(
                familyMemberRepository,
                familyMemberLinkRepository,
                userRepository,
                patientRepository,
                passwordEncoder,
                emailService,
                analyticsService,
                gamificationService
        );

        patientUser = new User();
        patientUser.setId(1L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);
        patientUser.setPassword("pass");

        familyUser = new User();
        familyUser.setId(2L);
        familyUser.setEmail("family@test.com");
        familyUser.setRole(Role.FAMILY_MEMBER);
        familyUser.setPassword("pass");

        grantedByUser = new User();
        grantedByUser.setId(3L);
        grantedByUser.setEmail("granter@test.com");
        grantedByUser.setRole(Role.PATIENT);
        grantedByUser.setPassword("pass");

        patient = Patient.builder()
                .id(10L)
                .firstName("John")
                .lastName("Doe")
                .email("patient@test.com")
                .phone("555-1234")
                .user(patientUser)
                .build();

        familyMember = FamilyMember.builder()
                .id(20L)
                .user(familyUser)
                .firstName("Jane")
                .lastName("Doe")
                .email("family@test.com")
                .build();

        link = new FamilyMemberLink(familyUser, patientUser, grantedByUser, "Son");
        link.setId(100L);
        link.setPatientId(10L);
        link.setCreatedAt(LocalDateTime.now());
    }

    @Test
    @DisplayName("registerFamilyMember - null email - throws BAD_REQUEST")
    void registerFamilyMember_nullEmail_throwsBadRequest() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", null, "555", null, "Son", 1L);
        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Email is required for family member registration", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - empty email - throws BAD_REQUEST")
    void registerFamilyMember_emptyEmail_throwsBadRequest() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "  ", "555", null, "Son", 1L);
        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Email is required for family member registration", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - null firstName - throws BAD_REQUEST")
    void registerFamilyMember_nullFirstName_throwsBadRequest() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                null, "Doe", "email@test.com", "555", null, "Son", 1L);
        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("First name is required for family member registration", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - null lastName - throws BAD_REQUEST")
    void registerFamilyMember_nullLastName_throwsBadRequest() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", null, "email@test.com", "555", null, "Son", 1L);
        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Last name is required for family member registration", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - null relationship - throws BAD_REQUEST")
    void registerFamilyMember_nullRelationship_throwsBadRequest() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "email@test.com", "555", null, null, 1L);
        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Relationship is required for family member registration", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - patient not found - throws NOT_FOUND")
    void registerFamilyMember_patientNotFound_throwsNotFound() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "email@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Patient not found", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - granter not found - throws NOT_FOUND")
    void registerFamilyMember_granterNotFound_throwsNotFound() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "email@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Granter user not found", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - existing user already linked - throws CONFLICT")
    void registerFamilyMember_existingUserAlreadyLinked_throwsConflict() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "family@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(userRepository.findByEmail("family@test.com")).thenReturn(Optional.of(familyUser));
        when(familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(true);

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("This family member is already linked to this patient", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - existing user not linked and is first link - creates link and unlocks achievement")
    void registerFamilyMember_existingUserNotLinkedFirstLink_createsLinkAndUnlocksAchievement() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "family@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(userRepository.findByEmail("family@test.com")).thenReturn(Optional.of(familyUser));
        when(familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(false);
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(eq(1L), any(LocalDateTime.class)))
                .thenReturn(List.of(link));

        final FamilyMemberLinkResponse response = familyMemberService.registerFamilyMember(reg, 3L);

        assertNotNull(response);
        verify(emailService).sendFamilyMemberAccessGrantedEmail(eq("family@test.com"), anyString(), anyString());
        verify(gamificationService).unlockAchievement(1L, "Added Family Member", 20);
    }

    @Test
    @DisplayName("registerFamilyMember - existing user not linked and not first link - no achievement")
    void registerFamilyMember_existingUserNotLinkedNotFirstLink_noAchievement() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "family@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(userRepository.findByEmail("family@test.com")).thenReturn(Optional.of(familyUser));
        when(familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(false);
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        final FamilyMemberLink link2 = new FamilyMemberLink();
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(eq(1L), any(LocalDateTime.class)))
                .thenReturn(List.of(link, link2));

        final FamilyMemberLinkResponse response = familyMemberService.registerFamilyMember(reg, 3L);

        assertNotNull(response);
        verify(gamificationService, never()).unlockAchievement(anyLong(), anyString(), anyInt());
    }

    @Test
    @DisplayName("registerFamilyMember - existing user not linked, patient profile not found - throws NOT_FOUND")
    void registerFamilyMember_existingUserNotLinkedPatientProfileNotFound_throwsNotFound() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "family@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(userRepository.findByEmail("family@test.com")).thenReturn(Optional.of(familyUser));
        when(familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(false);
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Patient profile not found", ex.getMessage());
    }

    @Test
    @DisplayName("registerFamilyMember - new user without address - creates user and family member")
    void registerFamilyMember_newUserWithoutAddress_createsUserAndFamilyMember() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "new@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(userRepository.findByEmail("new@test.com")).thenReturn(Optional.empty());
        when(passwordEncoder.encode(anyString())).thenReturn("encodedPassword");
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(any())).thenReturn(Optional.empty());

        final FamilyMemberLinkResponse response = familyMemberService.registerFamilyMember(reg, 3L);

        assertNotNull(response);
        verify(userRepository).save(any(User.class));
        verify(familyMemberRepository).save(any(FamilyMember.class));
        verify(emailService).sendPasswordSetupEmailWithCredentials(
                eq("new@test.com"), anyString(), eq("Jane"), eq("new@test.com"), anyString());
    }

    @Test
    @DisplayName("registerFamilyMember - new user with address - creates user with address")
    void registerFamilyMember_newUserWithAddress_createsUserWithAddress() throws Exception {
        final AddressDto addressDto = new AddressDto("123 Main St", "Apt 2", "Springfield", "IL", "62701", "555-5555");
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "new@test.com", "555", addressDto, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(userRepository.findByEmail("new@test.com")).thenReturn(Optional.empty());
        when(passwordEncoder.encode(anyString())).thenReturn("encodedPassword");
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(any())).thenReturn(Optional.empty());

        final FamilyMemberLinkResponse response = familyMemberService.registerFamilyMember(reg, 3L);

        assertNotNull(response);
        verify(familyMemberRepository).save(argThat(fm -> fm.getAddress() != null));
    }

    @Test
    @DisplayName("registerFamilyMember - password encoder returns null - throws INTERNAL_SERVER_ERROR")
    void registerFamilyMember_passwordEncoderReturnsNull_throwsInternalServerError() throws Exception {
        final FamilyMemberRegistration reg = new FamilyMemberRegistration(
                "Jane", "Doe", "new@test.com", "555", null, "Son", 1L);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(userRepository.findByEmail("new@test.com")).thenReturn(Optional.empty());
        when(passwordEncoder.encode(anyString())).thenReturn(null);

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.registerFamilyMember(reg, 3L));
        assertEquals("Failed to encode password", ex.getMessage());
    }

    @Test
    @DisplayName("getAccessiblePatients - with active links and patient found - returns patient data")
    void getAccessiblePatients_withActiveLinksPatientFound_returnsPatientData() throws Exception {
        when(familyMemberLinkRepository.findActivePatientsByFamilyMember(eq(2L), any(LocalDateTime.class)))
                .thenReturn(List.of(link));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(analyticsService.getDashboard(eq(1L), any(Period.class))).thenReturn(null);
        when(analyticsService.getVitals(eq(1L), any(Period.class))).thenReturn(List.of());

        final List<PatientDataResponse> result = familyMemberService.getAccessiblePatients(2L);

        assertEquals(1, result.size());
        assertEquals("John Doe", result.get(0).patientName());
        assertEquals("READ_ONLY", result.get(0).accessLevel());
        assertEquals("555-1234", result.get(0).phone());
    }

    @Test
    @DisplayName("getAccessiblePatients - patient profile not found - uses email as name")
    void getAccessiblePatients_patientProfileNotFound_usesEmailAsName() throws Exception {
        when(familyMemberLinkRepository.findActivePatientsByFamilyMember(eq(2L), any(LocalDateTime.class)))
                .thenReturn(List.of(link));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());
        when(analyticsService.getDashboard(eq(1L), any(Period.class))).thenReturn(null);
        when(analyticsService.getVitals(eq(1L), any(Period.class))).thenReturn(List.of());

        final List<PatientDataResponse> result = familyMemberService.getAccessiblePatients(2L);

        assertEquals(1, result.size());
        assertEquals("patient@test.com", result.get(0).patientName());
        assertNull(result.get(0).phone());
    }

    @Test
    @DisplayName("getAccessiblePatients - no links - returns empty list")
    void getAccessiblePatients_noLinks_returnsEmptyList() throws Exception {
        when(familyMemberLinkRepository.findActivePatientsByFamilyMember(eq(2L), any(LocalDateTime.class)))
                .thenReturn(List.of());

        final List<PatientDataResponse> result = familyMemberService.getAccessiblePatients(2L);

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPatientData - valid access - returns patient data")
    void getPatientData_validAccess_returnsPatientData() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(familyMemberLinkRepository.findByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(Optional.of(link));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(analyticsService.getDashboard(eq(1L), any(Period.class))).thenReturn(null);
        when(analyticsService.getVitals(eq(1L), any(Period.class))).thenReturn(List.of());
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));

        final PatientDataResponse result = familyMemberService.getPatientData(2L, 1L);

        assertNotNull(result);
        assertEquals("John Doe", result.patientName());
    }

    @Test
    @DisplayName("getPatientData - family member not found - throws NOT_FOUND")
    void getPatientData_familyMemberNotFound_throwsNotFound() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.getPatientData(2L, 1L));
        assertEquals("Family member not found", ex.getMessage());
    }

    @Test
    @DisplayName("getPatientData - patient not found - throws NOT_FOUND")
    void getPatientData_patientNotFound_throwsNotFound() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.getPatientData(2L, 1L));
        assertEquals("Patient not found", ex.getMessage());
    }

    @Test
    @DisplayName("getPatientData - no active link - throws FORBIDDEN")
    void getPatientData_noActiveLink_throwsForbidden() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(familyMemberLinkRepository.findByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.getPatientData(2L, 1L));
        assertEquals("Access denied to patient data", ex.getMessage());
    }

    @Test
    @DisplayName("getFamilyMembersByPatient - with results - returns link responses")
    void getFamilyMembersByPatient_withResults_returnsLinkResponses() throws Exception {
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(eq(1L), any(LocalDateTime.class)))
                .thenReturn(List.of(link));
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final List<FamilyMemberLinkResponse> result = familyMemberService.getFamilyMembersByPatient(1L);

        assertEquals(1, result.size());
        assertEquals("Jane Doe", result.get(0).familyMemberName());
        assertEquals("John Doe", result.get(0).patientName());
    }

    @Test
    @DisplayName("getFamilyMembersByPatient - empty list - returns empty")
    void getFamilyMembersByPatient_emptyList_returnsEmpty() throws Exception {
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(eq(1L), any(LocalDateTime.class)))
                .thenReturn(List.of());

        final List<FamilyMemberLinkResponse> result = familyMemberService.getFamilyMembersByPatient(1L);

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("revokeFamilyMemberAccess - link found - revokes link")
    void revokeFamilyMemberAccess_linkFound_revokesLink() throws Exception {
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));

        familyMemberService.revokeFamilyMemberAccess(100L, 3L);

        assertEquals(FamilyMemberLink.LinkStatus.REVOKED, link.getStatus());
        verify(familyMemberLinkRepository).save(link);
    }

    @Test
    @DisplayName("revokeFamilyMemberAccess - link not found - throws NOT_FOUND")
    void revokeFamilyMemberAccess_linkNotFound_throwsNotFound() throws Exception {
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.revokeFamilyMemberAccess(100L, 3L));
        assertEquals("Family member link not found", ex.getMessage());
    }

    @Test
    @DisplayName("hasAccessToPatient - both users found and link exists - returns true")
    void hasAccessToPatient_bothUsersFoundAndLinkExists_returnsTrue() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(familyMemberLinkRepository.existsActiveNonExpiredLink(eq(familyUser), eq(patientUser), any(LocalDateTime.class)))
                .thenReturn(true);

        assertTrue(familyMemberService.hasAccessToPatient(2L, 1L));
    }

    @Test
    @DisplayName("hasAccessToPatient - family user not found - returns false")
    void hasAccessToPatient_familyUserNotFound_returnsFalse() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.empty());
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));

        assertFalse(familyMemberService.hasAccessToPatient(2L, 1L));
    }

    @Test
    @DisplayName("hasAccessToPatient - patient user not found - returns false")
    void hasAccessToPatient_patientUserNotFound_returnsFalse() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.empty());

        assertFalse(familyMemberService.hasAccessToPatient(2L, 1L));
    }

    @Test
    @DisplayName("hasAccessToPatient - no active link - returns false")
    void hasAccessToPatient_noActiveLink_returnsFalse() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(familyMemberLinkRepository.existsActiveNonExpiredLink(eq(familyUser), eq(patientUser), any(LocalDateTime.class)))
                .thenReturn(false);

        assertFalse(familyMemberService.hasAccessToPatient(2L, 1L));
    }

    @Test
    @DisplayName("createTemporaryLink - valid inputs - creates temporary link")
    void createTemporaryLink_validInputs_createsTemporaryLink() throws Exception {
        final LocalDateTime expiresAt = LocalDateTime.now().plusDays(7);
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(false);
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));

        final FamilyMemberLinkResponse result = familyMemberService.createTemporaryLink(
                2L, 1L, "Son", expiresAt, "Temporary access", 3L);

        assertNotNull(result);
        verify(familyMemberLinkRepository).save(any(FamilyMemberLink.class));
    }

    @Test
    @DisplayName("createTemporaryLink - family member not found - throws NOT_FOUND")
    void createTemporaryLink_familyMemberNotFound_throwsNotFound() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.createTemporaryLink(2L, 1L, "Son",
                        LocalDateTime.now().plusDays(7), "notes", 3L));
        assertEquals("Family member not found", ex.getMessage());
    }

    @Test
    @DisplayName("createTemporaryLink - active link already exists - throws CONFLICT")
    void createTemporaryLink_activeLinkExists_throwsConflict() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(familyUser));
        when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
        when(userRepository.findById(3L)).thenReturn(Optional.of(grantedByUser));
        when(familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)).thenReturn(true);

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.createTemporaryLink(2L, 1L, "Son",
                        LocalDateTime.now().plusDays(7), "notes", 3L));
        assertEquals("Active link already exists", ex.getMessage());
    }

    @Test
    @DisplayName("updateFamilyMemberLink - all fields set - updates all fields")
    void updateFamilyMemberLink_allFieldsSet_updatesAllFields() throws Exception {
        final UpdateLinkRequest request = new UpdateLinkRequest("SUSPENDED", "TEMPORARY",
                LocalDateTime.now().plusDays(7), "Test notes");
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.updateFamilyMemberLink(100L, request, 3L);

        assertNotNull(result);
        assertEquals(FamilyMemberLink.LinkStatus.SUSPENDED, link.getStatus());
        assertEquals(FamilyMemberLink.LinkType.TEMPORARY, link.getLinkType());
        assertEquals("Test notes", link.getNotes());
    }

    @Test
    @DisplayName("updateFamilyMemberLink - null fields - no changes")
    void updateFamilyMemberLink_nullFields_noChanges() throws Exception {
        final UpdateLinkRequest request = new UpdateLinkRequest(null, null, null, null);
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.updateFamilyMemberLink(100L, request, 3L);

        assertNotNull(result);
        assertEquals(FamilyMemberLink.LinkStatus.ACTIVE, link.getStatus());
    }

    @Test
    @DisplayName("updateFamilyMemberLink - link not found - throws NOT_FOUND")
    void updateFamilyMemberLink_linkNotFound_throwsNotFound() throws Exception {
        final UpdateLinkRequest request = new UpdateLinkRequest("SUSPENDED", null, null, null);
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.updateFamilyMemberLink(100L, request, 3L));
        assertEquals("Family member link not found", ex.getMessage());
    }

    @Test
    @DisplayName("suspendFamilyMemberAccess - link found - suspends link")
    void suspendFamilyMemberAccess_linkFound_suspendsLink() throws Exception {
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.suspendFamilyMemberAccess(100L, 3L);

        assertNotNull(result);
        assertEquals(FamilyMemberLink.LinkStatus.SUSPENDED, link.getStatus());
    }

    @Test
    @DisplayName("suspendFamilyMemberAccess - link not found - throws NOT_FOUND")
    void suspendFamilyMemberAccess_linkNotFound_throwsNotFound() throws Exception {
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.suspendFamilyMemberAccess(100L, 3L));
        assertEquals("Family member link not found", ex.getMessage());
    }

    @Test
    @DisplayName("reactivateFamilyMemberAccess - suspended link - reactivates link")
    void reactivateFamilyMemberAccess_suspendedLink_reactivatesLink() throws Exception {
        link.setStatus(FamilyMemberLink.LinkStatus.SUSPENDED);
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any(FamilyMemberLink.class))).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.reactivateFamilyMemberAccess(100L, 3L);

        assertNotNull(result);
        assertEquals(FamilyMemberLink.LinkStatus.ACTIVE, link.getStatus());
    }

    @Test
    @DisplayName("reactivateFamilyMemberAccess - not suspended - throws BAD_REQUEST")
    void reactivateFamilyMemberAccess_notSuspended_throwsBadRequest() throws Exception {
        link.setStatus(FamilyMemberLink.LinkStatus.ACTIVE);
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.reactivateFamilyMemberAccess(100L, 3L));
        assertEquals("Only suspended links can be reactivated", ex.getMessage());
    }

    @Test
    @DisplayName("reactivateFamilyMemberAccess - link not found - throws NOT_FOUND")
    void reactivateFamilyMemberAccess_linkNotFound_throwsNotFound() throws Exception {
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> familyMemberService.reactivateFamilyMemberAccess(100L, 3L));
        assertEquals("Family member link not found", ex.getMessage());
    }

    @Test
    @DisplayName("cleanupExpiredFamilyMemberLinks - active and expired links - marks expired links")
    void cleanupExpiredFamilyMemberLinks_activeAndExpiredLinks_marksExpiredLinks() throws Exception {
        final FamilyMemberLink expiredLink = new FamilyMemberLink();
        expiredLink.setStatus(FamilyMemberLink.LinkStatus.ACTIVE);
        expiredLink.setExpiresAt(LocalDateTime.now().minusDays(1));

        final FamilyMemberLink activeLink = new FamilyMemberLink();
        activeLink.setStatus(FamilyMemberLink.LinkStatus.ACTIVE);
        activeLink.setExpiresAt(LocalDateTime.now().plusDays(1));

        final FamilyMemberLink suspendedLink = new FamilyMemberLink();
        suspendedLink.setStatus(FamilyMemberLink.LinkStatus.SUSPENDED);
        suspendedLink.setExpiresAt(LocalDateTime.now().minusDays(1));

        when(familyMemberLinkRepository.findAll())
                .thenReturn(List.of(expiredLink, activeLink, suspendedLink));

        familyMemberService.cleanupExpiredFamilyMemberLinks();

        assertEquals(FamilyMemberLink.LinkStatus.EXPIRED, expiredLink.getStatus());
        assertEquals(FamilyMemberLink.LinkStatus.ACTIVE, activeLink.getStatus());
        assertEquals(FamilyMemberLink.LinkStatus.SUSPENDED, suspendedLink.getStatus());
        verify(familyMemberLinkRepository, times(1)).save(expiredLink);
    }

    @Test
    @DisplayName("cleanupExpiredFamilyMemberLinks - no links - does nothing")
    void cleanupExpiredFamilyMemberLinks_noLinks_doesNothing() throws Exception {
        when(familyMemberLinkRepository.findAll()).thenReturn(List.of());

        familyMemberService.cleanupExpiredFamilyMemberLinks();

        verify(familyMemberLinkRepository, never()).save(any());
    }

    @Test
    @DisplayName("toFamilyMemberLinkResponse - grantedBy null - shows System")
    void toFamilyMemberLinkResponse_grantedByNull_showsSystem() throws Exception {
        final FamilyMemberLink linkNoGrantor = new FamilyMemberLink(familyUser, patientUser, null, "Son");
        linkNoGrantor.setId(200L);
        when(familyMemberLinkRepository.findById(200L)).thenReturn(Optional.of(linkNoGrantor));
        when(familyMemberLinkRepository.save(any())).thenReturn(linkNoGrantor);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.suspendFamilyMemberAccess(200L, 3L);

        assertEquals("System", result.grantedBy());
    }

    @Test
    @DisplayName("toFamilyMemberLinkResponse - family member not in repo - uses email")
    void toFamilyMemberLinkResponse_familyMemberNotInRepo_usesEmail() throws Exception {
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any())).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.empty());
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.suspendFamilyMemberAccess(100L, 3L);

        assertEquals("family@test.com", result.familyMemberName());
    }

    @Test
    @DisplayName("toFamilyMemberLinkResponse - patient not in repo - uses email")
    void toFamilyMemberLinkResponse_patientNotInRepo_usesEmail() throws Exception {
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any())).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

        final FamilyMemberLinkResponse result = familyMemberService.suspendFamilyMemberAccess(100L, 3L);

        assertEquals("patient@test.com", result.patientName());
    }

    @Test
    @DisplayName("getUserName - FAMILY_MEMBER role grantedBy - returns family member name")
    void getUserName_familyMemberRoleGrantedBy_returnsFamilyMemberName() throws Exception {
        grantedByUser.setRole(Role.FAMILY_MEMBER);
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any())).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(familyMemberRepository.findByUser(grantedByUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.suspendFamilyMemberAccess(100L, 3L);

        assertEquals("Jane Doe", result.grantedBy());
    }

    @Test
    @DisplayName("getUserName - CAREGIVER role grantedBy - returns email")
    void getUserName_caregiverRoleGrantedBy_returnsEmail() throws Exception {
        grantedByUser.setRole(Role.CAREGIVER);
        when(familyMemberLinkRepository.findById(100L)).thenReturn(Optional.of(link));
        when(familyMemberLinkRepository.save(any())).thenReturn(link);
        when(familyMemberRepository.findByUser(familyUser)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        final FamilyMemberLinkResponse result = familyMemberService.suspendFamilyMemberAccess(100L, 3L);

        assertEquals("granter@test.com", result.grantedBy());
    }
}
