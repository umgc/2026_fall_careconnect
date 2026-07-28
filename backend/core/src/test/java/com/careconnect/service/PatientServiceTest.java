package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.model.*;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class PatientServiceTest {

    @Mock
    private PatientRepository patientRepository;

    @Mock
    private CaregiverRepository caregiverRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Mock
    private AllergyService allergyService;

    @Mock
    private MedicationService medicationService;

    @Mock
    private VitalSampleService vitalSampleService;

    @Mock
    private MoodPainLogService moodPainLogService;

    @Mock
    private FamilyMemberService familyMemberService;

    @InjectMocks
    private PatientService patientService;

    private User user;
    private Patient patient;
    private Provider provider;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        user = User.builder()
                .id(100L)
                .name("John Doe")
                .email("john@test.com")
                .password("pass")
                .role(com.careconnect.security.Role.PATIENT)
                .build();

        provider = Provider.builder()
                .id(1L)
                .name("Dr. Smith")
                .specialty("Internal Medicine")
                .organization("Hospital")
                .phone("555-0100")
                .email("smith@hospital.com")
                .build();

        patient = Patient.builder()
                .id(1L)
                .firstName("John")
                .lastName("Doe")
                .email("john@test.com")
                .phone("555-1234")
                .dob("1990-01-01")
                .gender(Gender.MALE)
                .address(Address.builder()
                        .line1("123 Main St")
                        .line2("Apt 4")
                        .city("Springfield")
                        .state("IL")
                        .zip("62701")
                        .build())
                .relationship("self")
                .user(user)
                .primaryCareProvider(provider)
                .build();
    }

    // ── getCaregiversByPatient ──

    @Test
    @DisplayName("getCaregiversByPatient_patientNotFound_throwsAppException")
    void getCaregiversByPatient_patientNotFound_throwsAppException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> patientService.getCaregiversByPatient(99L));
        assertEquals("Patient not found", ex.getMessage());
    }

    @Test
    @DisplayName("getCaregiversByPatient_noActiveLinks_returnsEmptyList")
    void getCaregiversByPatient_noActiveLinks_returnsEmptyList() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());

        final List<Caregiver> result = patientService.getCaregiversByPatient(1L);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getCaregiversByPatient_activeLinksExist_returnsCaregiverList")
    void getCaregiversByPatient_activeLinksExist_returnsCaregiverList() throws Exception {
        final User caregiverUser = User.builder().id(200L).name("Jane Caregiver")
                .email("jane@test.com").password("pass")
                .role(com.careconnect.security.Role.CAREGIVER).build();
        final Caregiver caregiver = Caregiver.builder().id(10L).firstName("Jane")
                .lastName("Caregiver").user(caregiverUser).build();

        final CaregiverPatientLinkResponse link = new CaregiverPatientLinkResponse(
                1L, 200L, "Jane Caregiver", "jane@test.com",
                100L, "John Doe", "john@test.com",
                "ACTIVE", "PRIMARY", false, false, LocalDateTime.now(), null, null, "system", true, false);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(List.of(link));
        when(userRepository.findById(200L)).thenReturn(Optional.of(caregiverUser));
        when(caregiverRepository.findByUser(caregiverUser)).thenReturn(Optional.of(caregiver));

        final List<Caregiver> result = patientService.getCaregiversByPatient(1L);
        assertEquals(1, result.size());
        assertEquals("Jane", result.get(0).getFirstName());
    }

    @Test
    @DisplayName("getCaregiversByPatient_userNotFoundForLink_filtersOutMissing")
    void getCaregiversByPatient_userNotFoundForLink_filtersOutMissing() throws Exception {
        final CaregiverPatientLinkResponse link = new CaregiverPatientLinkResponse(
                1L, 999L, "Missing", "missing@test.com",
                100L, "John Doe", "john@test.com",
                "ACTIVE", "PRIMARY", false, false, LocalDateTime.now(), null, null, "system", true, false);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(List.of(link));
        when(userRepository.findById(999L)).thenReturn(Optional.empty());

        final List<Caregiver> result = patientService.getCaregiversByPatient(1L);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getCaregiversByPatient_caregiverNotFoundForUser_filtersOutMissing")
    void getCaregiversByPatient_caregiverNotFoundForUser_filtersOutMissing() throws Exception {
        final User caregiverUser = User.builder().id(200L).name("Jane")
                .email("jane@test.com").password("pass")
                .role(com.careconnect.security.Role.CAREGIVER).build();

        final CaregiverPatientLinkResponse link = new CaregiverPatientLinkResponse(
                1L, 200L, "Jane", "jane@test.com",
                100L, "John Doe", "john@test.com",
                "ACTIVE", "PRIMARY", false, false, LocalDateTime.now(), null, null, "system", true, false);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(List.of(link));
        when(userRepository.findById(200L)).thenReturn(Optional.of(caregiverUser));
        when(caregiverRepository.findByUser(caregiverUser)).thenReturn(Optional.empty());

        final List<Caregiver> result = patientService.getCaregiversByPatient(1L);
        assertTrue(result.isEmpty());
    }

    // ── getPatientById ──

    @Test
    @DisplayName("getPatientById_patientExists_returnsPatient")
    void getPatientById_patientExists_returnsPatient() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));

        final Patient result = patientService.getPatientById(1L);
        assertEquals("John", result.getFirstName());
    }

    @Test
    @DisplayName("getPatientById_patientNotFound_throwsAppException")
    void getPatientById_patientNotFound_throwsAppException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> patientService.getPatientById(99L));
        assertEquals("Patient not found", ex.getMessage());
    }

    // ── getPatientByUserId ──

    @Test
    @DisplayName("getPatientByUserId_userAndPatientExist_returnsPatient")
    void getPatientByUserId_userAndPatientExist_returnsPatient() throws Exception {
        when(userRepository.findById(100L)).thenReturn(Optional.of(user));
        when(patientRepository.findByUser(user)).thenReturn(Optional.of(patient));

        final Patient result = patientService.getPatientByUserId(100L);
        assertEquals("John", result.getFirstName());
    }

    @Test
    @DisplayName("getPatientByUserId_userNotFound_throwsAppException")
    void getPatientByUserId_userNotFound_throwsAppException() throws Exception {
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> patientService.getPatientByUserId(99L));
        assertEquals("User not found", ex.getMessage());
    }

    @Test
    @DisplayName("getPatientByUserId_patientNotFound_throwsAppException")
    void getPatientByUserId_patientNotFound_throwsAppException() throws Exception {
        when(userRepository.findById(100L)).thenReturn(Optional.of(user));
        when(patientRepository.findByUser(user)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> patientService.getPatientByUserId(100L));
        assertEquals("Patient profile not found", ex.getMessage());
    }

    // ── updatePatient ──

    @Test
    @DisplayName("updatePatient_patientExists_updatesAndReturnsPatient")
    void updatePatient_patientExists_updatesAndReturnsPatient() throws Exception {
        final Patient updatedData = Patient.builder()
                .firstName("Jane")
                .lastName("Smith")
                .dob("1985-06-15")
                .email("jane@test.com")
                .phone("555-9876")
                .address(Address.builder().line1("456 Elm St").build())
                .relationship("spouse")
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> inv.getArgument(0));

        final Patient result = patientService.updatePatient(1L, updatedData);
        assertEquals("Jane", result.getFirstName());
        assertEquals("Smith", result.getLastName());
        assertEquals("spouse", result.getRelationship());
    }

    @Test
    @DisplayName("updatePatient_patientNotFound_throwsAppException")
    void updatePatient_patientNotFound_throwsAppException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> patientService.updatePatient(99L, new Patient()));
        assertEquals("Patient not found", ex.getMessage());
    }

    // ── existsByUserId ──

    @Test
    @DisplayName("existsByUserId_userExistsAndPatientExists_returnsTrue")
    void existsByUserId_userExistsAndPatientExists_returnsTrue() throws Exception {
        when(userRepository.findById(100L)).thenReturn(Optional.of(user));
        when(patientRepository.existsByUser(user)).thenReturn(true);

        assertTrue(patientService.existsByUserId(100L));
    }

    @Test
    @DisplayName("existsByUserId_userNotFound_returnsFalse")
    void existsByUserId_userNotFound_returnsFalse() throws Exception {
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertFalse(patientService.existsByUserId(99L));
    }

    @Test
    @DisplayName("existsByUserId_userExistsButNoPatient_returnsFalse")
    void existsByUserId_userExistsButNoPatient_returnsFalse() throws Exception {
        when(userRepository.findById(100L)).thenReturn(Optional.of(user));
        when(patientRepository.existsByUser(user)).thenReturn(false);

        assertFalse(patientService.existsByUserId(100L));
    }

    // ── getPrimaryProvider ──

    @Test
    @DisplayName("getPrimaryProvider_patientHasProvider_returnsProviderMap")
    void getPrimaryProvider_patientHasProvider_returnsProviderMap() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));

        final Map<String, Object> result = patientService.getPrimaryProvider(1L);
        assertEquals("Dr. Smith", result.get("name"));
        assertEquals("Internal Medicine", result.get("specialty"));
        assertEquals("Hospital", result.get("organization"));
        assertEquals("555-0100", result.get("phone"));
        assertEquals("smith@hospital.com", result.get("email"));
    }

    @Test
    @DisplayName("getPrimaryProvider_patientHasNoProvider_returnsEmptyMap")
    void getPrimaryProvider_patientHasNoProvider_returnsEmptyMap() throws Exception {
        patient.setPrimaryCareProvider(null);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));

        final Map<String, Object> result = patientService.getPrimaryProvider(1L);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPrimaryProvider_patientNotFound_throwsIllegalArgumentException")
    void getPrimaryProvider_patientNotFound_throwsIllegalArgumentException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class,
                () -> patientService.getPrimaryProvider(99L));
    }

    // ── getPatientProfile ──

    @Test
    @DisplayName("getPatientProfile_patientExists_returnsProfileDTO")
    void getPatientProfile_patientExists_returnsProfileDTO() throws Exception {
        final List<AllergyDTO> allergies = List.of(AllergyDTO.builder().id(1L).allergen("Peanuts").build());
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(allergies);

        final Optional<PatientProfileDTO> result = patientService.getPatientProfile(1L);
        assertTrue(result.isPresent());
        assertEquals("John", result.get().firstName());
        assertEquals("Doe", result.get().lastName());
        assertEquals(1, result.get().allergies().size());
        assertNotNull(result.get().address());
    }

    @Test
    @DisplayName("getPatientProfile_patientNotFound_returnsEmpty")
    void getPatientProfile_patientNotFound_returnsEmpty() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final Optional<PatientProfileDTO> result = patientService.getPatientProfile(99L);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPatientProfile_patientWithNullAddress_returnsNullAddress")
    void getPatientProfile_patientWithNullAddress_returnsNullAddress() throws Exception {
        patient.setAddress(null);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());

        final Optional<PatientProfileDTO> result = patientService.getPatientProfile(1L);
        assertTrue(result.isPresent());
        assertNull(result.get().address());
    }

    // ── updatePatientProfile ──

    @Test
    @DisplayName("updatePatientProfile_allFieldsProvided_updatesAllFields")
    void updatePatientProfile_allFieldsProvided_updatesAllFields() throws Exception {
        final PatientProfileUpdateDTO updateDTO = new PatientProfileUpdateDTO();
        updateDTO.setFirstName("Jane");
        updateDTO.setLastName("Smith");
        updateDTO.setPhone("555-9999");
        updateDTO.setDob("1985-06-15");
        updateDTO.setGender(Gender.FEMALE);
        updateDTO.setAddress(new AddressDto("456 Oak Ave", "Suite 2", "Chicago", "IL", "60601", null));
        updateDTO.setRelationship("daughter");

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> inv.getArgument(0));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());

        final PatientProfileDTO result = patientService.updatePatientProfile(1L, updateDTO);
        assertEquals("Jane", result.firstName());
        assertEquals("Smith", result.lastName());
        assertEquals("555-9999", result.phone());
        assertEquals("daughter", result.relationship());
    }

    @Test
    @DisplayName("updatePatientProfile_nullFieldsNotUpdated_keepsExistingValues")
    void updatePatientProfile_nullFieldsNotUpdated_keepsExistingValues() throws Exception {
        final PatientProfileUpdateDTO updateDTO = new PatientProfileUpdateDTO();
        // All fields are null by default

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> inv.getArgument(0));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());

        final PatientProfileDTO result = patientService.updatePatientProfile(1L, updateDTO);
        assertEquals("John", result.firstName());
        assertEquals("Doe", result.lastName());
    }

    @Test
    @DisplayName("updatePatientProfile_patientNotFound_throwsIllegalArgException")
    void updatePatientProfile_patientNotFound_throwsIllegalArgException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class,
                () -> patientService.updatePatientProfile(99L, new PatientProfileUpdateDTO()));
    }

    @Test
    @DisplayName("updatePatientProfile_nullAddress_setsNullAddress")
    void updatePatientProfile_nullAddress_setsNullAddress() throws Exception {
        final PatientProfileUpdateDTO updateDTO = new PatientProfileUpdateDTO();
        updateDTO.setFirstName("Jane");
        // address is left null

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> inv.getArgument(0));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());

        final PatientProfileDTO result = patientService.updatePatientProfile(1L, updateDTO);
        assertEquals("Jane", result.firstName());
        // existing address should remain since address was null in update
    }

    // ── getEnhancedPatientProfile ──

    @Test
    @DisplayName("getEnhancedPatientProfile_patientNotFound_returnsEmpty")
    void getEnhancedPatientProfile_patientNotFound_returnsEmpty() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(99L);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_fullData_returnsCompleteProfile")
    void getEnhancedPatientProfile_fullData_returnsCompleteProfile() throws Exception {
        final Instant now = Instant.now();
        final LocalDateTime nowLocal = LocalDateTime.now();

        final List<AllergyDTO> allergies = List.of(AllergyDTO.builder().id(1L).allergen("Peanuts").build());
        final List<MedicationDTO> meds = List.of(MedicationDTO.builder().id(1L).medicationName("Aspirin").build());

        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 72.0, 98.0, 120, 80, 150.0, null, 7, 3);

        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(3).note("Feeling okay")
                .timestamp(nowLocal).createdAt(nowLocal).build();

        final CaregiverPatientLinkResponse caregiverLink = new CaregiverPatientLinkResponse(
                5L, 200L, "Caregiver", "cg@test.com",
                100L, "John Doe", "john@test.com",
                "ACTIVE", "PRIMARY", false, false, nowLocal, null, null, "system", true, false);

        final FamilyMemberLinkResponse familyLink = new FamilyMemberLinkResponse(
                10L, 300L, "Family Member", "fm@test.com",
                100L, "John Doe", "daughter", "ACTIVE", nowLocal, "system");

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(allergies);
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(meds);
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(List.of(caregiverLink));
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(List.of(familyLink));

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertEquals("John", result.get().firstName());
        assertEquals(1, result.get().allergies().size());
        assertEquals(1, result.get().activeMedications().size());
        assertNotNull(result.get().latestVitals());
        assertNotNull(result.get().latestMoodPain());
        assertNotNull(result.get().medicalSummary());
        assertEquals(5L, result.get().caregiverId());
        assertEquals(10L, result.get().familyMemberId());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_noLinksExist_returnsNullIds")
    void getEnhancedPatientProfile_noLinksExist_returnsNullIds() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertNull(result.get().caregiverId());
        assertNull(result.get().familyMemberId());
        assertNull(result.get().latestVitals());
        assertNull(result.get().latestMoodPain());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_vitalSampleServiceThrows_latestVitalsNull")
    void getEnhancedPatientProfile_vitalSampleServiceThrows_latestVitalsNull() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenThrow(new RuntimeException("DB error"));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertNull(result.get().latestVitals());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_moodPainServiceThrows_latestMoodPainNull")
    void getEnhancedPatientProfile_moodPainServiceThrows_latestMoodPainNull() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenThrow(new RuntimeException("DB error"));
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertNull(result.get().latestMoodPain());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_patientNotInRepoForMoodPain_moodPainNull")
    void getEnhancedPatientProfile_patientNotInRepoForMoodPain_moodPainNull() throws Exception {
        // First findById for the main method succeeds, but the one inside getLatestMoodPain returns empty
        when(patientRepository.findById(1L))
                .thenReturn(Optional.of(patient))
                .thenReturn(Optional.empty());
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertNull(result.get().latestMoodPain());
    }

    // ── determineHealthStatus (tested indirectly via getEnhancedPatientProfile) ──

    @Test
    @DisplayName("getEnhancedPatientProfile_warningHeartRate_healthStatusNeedsAttention")
    void getEnhancedPatientProfile_warningHeartRate_healthStatusNeedsAttention() throws Exception {
        final Instant now = Instant.now();
        // Heart rate > 100 triggers warning
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 110.0, 98.0, 120, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertEquals("Needs Attention", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_lowHeartRate_healthStatusNeedsAttention")
    void getEnhancedPatientProfile_lowHeartRate_healthStatusNeedsAttention() throws Exception {
        final Instant now = Instant.now();
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 50.0, 98.0, 120, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Needs Attention", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_highSystolic_healthStatusNeedsAttention")
    void getEnhancedPatientProfile_highSystolic_healthStatusNeedsAttention() throws Exception {
        final Instant now = Instant.now();
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 75.0, 98.0, 150, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Needs Attention", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_lowSystolic_healthStatusNeedsAttention")
    void getEnhancedPatientProfile_lowSystolic_healthStatusNeedsAttention() throws Exception {
        final Instant now = Instant.now();
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 75.0, 98.0, 85, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Needs Attention", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_lowSpo2_healthStatusNeedsAttention")
    void getEnhancedPatientProfile_lowSpo2_healthStatusNeedsAttention() throws Exception {
        final Instant now = Instant.now();
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 75.0, 90.0, 120, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Needs Attention", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_highPain_healthStatusNeedsAttention")
    void getEnhancedPatientProfile_highPain_healthStatusNeedsAttention() throws Exception {
        final LocalDateTime nowLocal = LocalDateTime.now();
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(8).note("High pain")
                .timestamp(nowLocal).createdAt(nowLocal).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Needs Attention", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_lowMood_healthStatusMonitorMood")
    void getEnhancedPatientProfile_lowMood_healthStatusMonitorMood() throws Exception {
        final LocalDateTime nowLocal = LocalDateTime.now();
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(2).painValue(2).note("Low mood")
                .timestamp(nowLocal).createdAt(nowLocal).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Monitor Mood", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_normalVitalsAndMood_healthStatusStable")
    void getEnhancedPatientProfile_normalVitalsAndMood_healthStatusStable() throws Exception {
        final Instant now = Instant.now();
        final LocalDateTime nowLocal = LocalDateTime.now();

        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 75.0, 98.0, 120, 80, 150.0, null, 7, 3);
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(2).note("Good")
                .timestamp(nowLocal).createdAt(nowLocal).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Stable", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_noVitalsNoMood_healthStatusNoRecentData")
    void getEnhancedPatientProfile_noVitalsNoMood_healthStatusNoRecentData() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("No Recent Data", result.get().medicalSummary().overallHealthStatus());
        assertEquals("No recent activity", result.get().medicalSummary().lastActivityDate());
    }

    // ── findLastActivityDate (tested indirectly) ──

    @Test
    @DisplayName("getEnhancedPatientProfile_onlyVitals_lastActivityDateFromVitals")
    void getEnhancedPatientProfile_onlyVitals_lastActivityDateFromVitals() throws Exception {
        final Instant now = Instant.now();
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 75.0, 98.0, 120, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertNotNull(result.get().medicalSummary().lastActivityDate());
        assertNotEquals("No recent activity", result.get().medicalSummary().lastActivityDate());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_onlyMoodPain_lastActivityDateFromMoodPain")
    void getEnhancedPatientProfile_onlyMoodPain_lastActivityDateFromMoodPain() throws Exception {
        final LocalDateTime nowLocal = LocalDateTime.now();
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(2).note("Good")
                .timestamp(nowLocal).createdAt(nowLocal).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertNotNull(result.get().medicalSummary().lastActivityDate());
        assertNotEquals("No recent activity", result.get().medicalSummary().lastActivityDate());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_vitalTimestampNull_handledGracefully")
    void getEnhancedPatientProfile_vitalTimestampNull_handledGracefully() throws Exception {
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, null, 75.0, 98.0, 120, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_moodPainTimestampNull_handledGracefully")
    void getEnhancedPatientProfile_moodPainTimestampNull_handledGracefully() throws Exception {
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(2).note("Good")
                .timestamp(null).createdAt(null).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_bothVitalsAndMoodPainPresent_vitalAfterMood_latestIsVitals")
    void getEnhancedPatientProfile_bothVitalsAndMoodPainPresent_vitalAfterMood_latestIsVitals() throws Exception {
        // Vitals timestamp is more recent than mood/pain
        final Instant vitalTime = Instant.now();
        final LocalDateTime moodTime = LocalDateTime.now().minusDays(2);

        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, vitalTime, 75.0, 98.0, 120, 80, 150.0, null, 7, 3);
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(2).note("Good")
                .timestamp(moodTime).createdAt(moodTime).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertNotNull(result.get().medicalSummary().lastActivityDate());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_bothVitalsAndMoodPainPresent_moodAfterVitals_latestIsMood")
    void getEnhancedPatientProfile_bothVitalsAndMoodPainPresent_moodAfterVitals_latestIsMood() throws Exception {
        // Mood/pain timestamp is more recent
        final Instant vitalTime = Instant.now().minus(3, ChronoUnit.DAYS);
        final LocalDateTime moodTime = LocalDateTime.now();

        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, vitalTime, 75.0, 98.0, 120, 80, 150.0, null, 7, 3);
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(2).note("Good")
                .timestamp(moodTime).createdAt(moodTime).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertNotNull(result.get().medicalSummary().lastActivityDate());
    }

    // ── buildMedicalSummary with null lists ──

    @Test
    @DisplayName("getEnhancedPatientProfile_nullAllergiesAndMeds_summaryCountsZero")
    void getEnhancedPatientProfile_nullAllergiesAndMeds_summaryCountsZero() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(null);
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(null);
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.isPresent());
        assertEquals(0, result.get().medicalSummary().totalAllergies());
        assertEquals(0, result.get().medicalSummary().activeMedications());
    }

    // ── determineHealthStatus: vitals with null fields ──

    @Test
    @DisplayName("getEnhancedPatientProfile_vitalsWithNullHeartRateAndSystolicAndSpo2_stableStatus")
    void getEnhancedPatientProfile_vitalsWithNullHeartRateAndSystolicAndSpo2_stableStatus() throws Exception {
        final Instant now = Instant.now();
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, null, null, null, null, null, null, null, null);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Stable", result.get().medicalSummary().overallHealthStatus());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_moodPainNullPainAndMoodValues_stable")
    void getEnhancedPatientProfile_moodPainNullPainAndMoodValues_stable() throws Exception {
        final LocalDateTime nowLocal = LocalDateTime.now();
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(null).painValue(null).note("No values")
                .timestamp(nowLocal).createdAt(nowLocal).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertEquals("Stable", result.get().medicalSummary().overallHealthStatus());
    }

    // ── hasRecentVitals / hasRecentMoodPain old timestamps ──

    @Test
    @DisplayName("getEnhancedPatientProfile_oldVitals_hasRecentVitalsFalse")
    void getEnhancedPatientProfile_oldVitals_hasRecentVitalsFalse() throws Exception {
        final Instant oldTime = Instant.now().minus(10, ChronoUnit.DAYS);
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, oldTime, 75.0, 98.0, 120, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertFalse(result.get().medicalSummary().hasRecentVitals());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_oldMoodPain_hasRecentMoodPainFalse")
    void getEnhancedPatientProfile_oldMoodPain_hasRecentMoodPainFalse() throws Exception {
        final LocalDateTime oldTime = LocalDateTime.now().minusDays(10);
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(2).note("Old")
                .timestamp(oldTime).createdAt(oldTime).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertFalse(result.get().medicalSummary().hasRecentMoodPain());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_recentVitals_hasRecentVitalsTrue")
    void getEnhancedPatientProfile_recentVitals_hasRecentVitalsTrue() throws Exception {
        final Instant now = Instant.now();
        final VitalSampleDTO vitalSample = new VitalSampleDTO(1L, 1L, now, 75.0, 98.0, 120, 80, 150.0, null, 7, 3);

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.of(vitalSample));
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(null);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.get().medicalSummary().hasRecentVitals());
    }

    @Test
    @DisplayName("getEnhancedPatientProfile_recentMoodPain_hasRecentMoodPainTrue")
    void getEnhancedPatientProfile_recentMoodPain_hasRecentMoodPainTrue() throws Exception {
        final LocalDateTime now = LocalDateTime.now();
        final MoodPainLogResponse moodPain = MoodPainLogResponse.builder()
                .id(1L).moodValue(7).painValue(2).note("Good")
                .timestamp(now).createdAt(now).build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(allergyService.getAllergiesForPatient(1L)).thenReturn(Collections.emptyList());
        when(medicationService.getAllMedicationsForPatient(1L)).thenReturn(Collections.emptyList());
        when(vitalSampleService.getLatestVitalSample(1L)).thenReturn(Optional.empty());
        when(moodPainLogService.getLatestMoodPainLog(user)).thenReturn(moodPain);
        when(caregiverPatientLinkService.getCaregiversByPatient(100L)).thenReturn(Collections.emptyList());
        when(familyMemberService.getFamilyMembersByPatientId(1L)).thenReturn(Collections.emptyList());

        final Optional<EnhancedPatientProfileDTO> result = patientService.getEnhancedPatientProfile(1L);
        assertTrue(result.get().medicalSummary().hasRecentMoodPain());
    }
}
