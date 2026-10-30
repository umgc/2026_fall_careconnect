package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.exception.RegistrationException;
import com.careconnect.model.*;
import com.careconnect.model.User;
import com.careconnect.repository.*;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.careconnect.dto.ProfessionalInfoDto;

class CaregiverServiceTest {

    @Mock
    private CaregiverRepository caregiverRepository;

    @Mock
    private PatientRepository patientRepository;

    @Mock
    private UserRepository users;

    @Mock
    private PasswordEncoder encoder;

    @Mock
    private JwtTokenProvider jwt;

    @Mock
    private EmailService emailService;

    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Mock
    private FamilyMemberLinkRepository familyMemberLinkRepository;

    @Mock
    private StripeService stripeService;

    @Mock
    private PlanRepository planRepository;

    @Mock
    private SubscriptionRepository subscriptionRepository;

    @Mock
    private PatientRiskService patientRiskService;

    @InjectMocks
    private CaregiverService caregiverService;

    private User caregiverUser;
    private Caregiver testCaregiver;
    private Patient testPatient;
    private User patientUser;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        caregiverUser = new User();
        caregiverUser.setId(1L);
        caregiverUser.setEmail("caregiver@test.com");
        caregiverUser.setRole(Role.CAREGIVER);
        caregiverUser.setStatus("ACTIVE");

        testCaregiver = Caregiver.builder()
                .id(10L)
                .firstName("Jane")
                .lastName("Smith")
                .email("caregiver@test.com")
                .phone("1234567890")
                .user(caregiverUser)
                .caregiverType("PROFESSIONAL")
                .build();

        patientUser = new User();
        patientUser.setId(2L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);

        testPatient = Patient.builder()
                .id(20L)
                .firstName("John")
                .lastName("Doe")
                .email("patient@test.com")
                .phone("9876543210")
                .dob("1990-01-01")
                .user(patientUser)
                .build();
    }

    // ==================== getPatientsByCaregiver Tests ====================

    @Nested
    @DisplayName("getPatientsByCaregiver tests")
    class GetPatientsByCaregiverTests {

        @Test
        @DisplayName("getPatientsByCaregiver_withActiveLinks_shouldReturnPatientList")
        void getPatientsByCaregiver_withActiveLinks_shouldReturnPatientList() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    2L, "John Doe", "patient@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));
            when(users.findById(2L)).thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(testPatient));

            final List<PatientWithLinkDto> result = caregiverService.getPatientsByCaregiver(10L, null, null);

            assertNotNull(result);
            assertEquals(1, result.size());
            assertEquals("John", result.get(0).patient().firstName());
            assertEquals("Doe", result.get(0).patient().lastName());
        }

        @Test
        @DisplayName("getPatientsByCaregiver_filterByEmail_shouldFilterCorrectly")
        void getPatientsByCaregiver_filterByEmail_shouldFilterCorrectly() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    2L, "John Doe", "patient@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));
            when(users.findById(2L)).thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(testPatient));

            // Filter by matching email
            final List<PatientWithLinkDto> result = caregiverService.getPatientsByCaregiver(10L, "patient@test.com", null);
            assertEquals(1, result.size());

            // Filter by non-matching email
            final List<PatientWithLinkDto> filtered = caregiverService.getPatientsByCaregiver(10L, "other@test.com", null);
            assertEquals(0, filtered.size());
        }

        @Test
        @DisplayName("getPatientsByCaregiver_filterByName_shouldFilterCorrectly")
        void getPatientsByCaregiver_filterByName_shouldFilterCorrectly() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    2L, "John Doe", "patient@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));
            when(users.findById(2L)).thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(testPatient));

            // Filter by matching name
            final List<PatientWithLinkDto> result = caregiverService.getPatientsByCaregiver(10L, null, "John");
            assertEquals(1, result.size());

            // Filter by non-matching name
            final List<PatientWithLinkDto> filtered = caregiverService.getPatientsByCaregiver(10L, null, "Alice");
            assertEquals(0, filtered.size());
        }

        @Test
        @DisplayName("getPatientsByCaregiver_userNotFound_shouldFilterOut")
        void getPatientsByCaregiver_userNotFound_shouldFilterOut() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    2L, "John Doe", "patient@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));
            when(users.findById(2L)).thenReturn(Optional.empty());

            final List<PatientWithLinkDto> result = caregiverService.getPatientsByCaregiver(10L, null, null);

            assertEquals(0, result.size());
        }

        @Test
        @DisplayName("getPatientsByCaregiver_patientNotFoundForUser_shouldFilterOut")
        void getPatientsByCaregiver_patientNotFoundForUser_shouldFilterOut() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    2L, "John Doe", "patient@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));
            when(users.findById(2L)).thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

            final List<PatientWithLinkDto> result = caregiverService.getPatientsByCaregiver(10L, null, null);

            assertEquals(0, result.size());
        }

        @Test
        @DisplayName("getPatientsByCaregiver_patientWithNullEmail_shouldFilterOutWhenEmailFilterProvided")
        void getPatientsByCaregiver_patientWithNullEmail_shouldFilterOutWhenEmailFilterProvided() throws Exception {
            final Patient patientWithNullEmail = Patient.builder()
                    .id(20L)
                    .firstName("John")
                    .lastName("Doe")
                    .email(null)
                    .user(patientUser)
                    .build();

            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    2L, "John Doe", "patient@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));
            when(users.findById(2L)).thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patientWithNullEmail));

            final List<PatientWithLinkDto> result = caregiverService.getPatientsByCaregiver(10L, "patient@test.com", null);

            assertEquals(0, result.size());
        }

        @Test
        @DisplayName("getPatientsByCaregiver_caregiverNotFound_shouldThrowRuntimeException")
        void getPatientsByCaregiver_caregiverNotFound_shouldThrowRuntimeException() throws Exception {
            when(caregiverRepository.findById(999L)).thenReturn(Optional.empty());

            assertThrows(RuntimeException.class,
                    () -> caregiverService.getPatientsByCaregiver(999L, null, null));
        }

        @Test
        @DisplayName("getPatientsByCaregiver_noActiveLinks_shouldReturnEmptyList")
        void getPatientsByCaregiver_noActiveLinks_shouldReturnEmptyList() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of());

            final List<PatientWithLinkDto> result = caregiverService.getPatientsByCaregiver(10L, null, null);

            assertNotNull(result);
            assertTrue(result.isEmpty());
        }
    }

    // ==================== getCaregiverById Tests ====================

    @Nested
    @DisplayName("getCaregiverById tests")
    class GetCaregiverByIdTests {

        @Test
        @DisplayName("getCaregiverById_validId_shouldReturnCaregiver")
        void getCaregiverById_validId_shouldReturnCaregiver() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final Caregiver result = caregiverService.getCaregiverById(10L);

            assertNotNull(result);
            assertEquals("Jane", result.getFirstName());
            assertEquals("Smith", result.getLastName());
        }

        @Test
        @DisplayName("getCaregiverById_notFound_shouldThrowRuntimeException")
        void getCaregiverById_notFound_shouldThrowRuntimeException() throws Exception {
            when(caregiverRepository.findById(999L)).thenReturn(Optional.empty());

            assertThrows(RuntimeException.class, () -> caregiverService.getCaregiverById(999L));
        }
    }

    // ==================== updateCaregiver Tests ====================

    @Nested
    @DisplayName("updateCaregiver tests")
    class UpdateCaregiverTests {

        @Test
        @DisplayName("updateCaregiver_validData_shouldUpdateAndReturn")
        void updateCaregiver_validData_shouldUpdateAndReturn() throws Exception {
            final Caregiver updatedData = Caregiver.builder()
                    .firstName("Updated")
                    .lastName("Name")
                    .dob("1985-01-01")
                    .email("updated@test.com")
                    .phone("5555555555")
                    .address(Address.builder().line1("New Addr").city("New City").state("CA").zip("90001").build())
                    .caregiverType("FAMILY")
                    .build();

            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(caregiverRepository.save(any(Caregiver.class))).thenReturn(testCaregiver);

            final Caregiver result = caregiverService.updateCaregiver(10L, updatedData);

            assertNotNull(result);
            verify(caregiverRepository).save(testCaregiver);
            assertEquals("Updated", testCaregiver.getFirstName());
            assertEquals("Name", testCaregiver.getLastName());
            assertEquals("updated@test.com", testCaregiver.getEmail());
            assertEquals("FAMILY", testCaregiver.getCaregiverType());
        }

        @Test
        @DisplayName("updateCaregiver_notFound_shouldThrowRuntimeException")
        void updateCaregiver_notFound_shouldThrowRuntimeException() throws Exception {
            when(caregiverRepository.findById(999L)).thenReturn(Optional.empty());

            assertThrows(RuntimeException.class,
                    () -> caregiverService.updateCaregiver(999L, new Caregiver()));
        }
    }

    // ==================== registerPatient Tests ====================

    @Nested
    @DisplayName("registerPatient tests")
    class RegisterPatientTests {

        @Test
        @DisplayName("registerPatient_validData_shouldCreatePatientAndSendEmail")
        void registerPatient_validData_shouldCreatePatientAndSendEmail() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            reg.setEmail("newpatient@test.com");
            reg.setFirstName("New");
            reg.setLastName("Patient");
            reg.setPhone("1234567890");
            reg.setDob("1990-01-01");
            reg.setAddress(new AddressDto("123 Main St", null, "City", "MD", "21001", null));

            when(users.existsByEmail("newpatient@test.com")).thenReturn(false);
            when(encoder.encode(anyString())).thenReturn("encodedPassword");
            when(users.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(5L);
                return u;
            });
            when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> {
                final Patient p = inv.getArgument(0);
                p.setId(25L);
                return p;
            });

            final Patient result = caregiverService.registerPatient(reg);

            assertNotNull(result);
            verify(users).save(any(User.class));
            verify(patientRepository).save(any(Patient.class));
            verify(emailService).sendPasswordSetupEmailWithCredentials(
                    eq("newpatient@test.com"), anyString(), eq("New"), eq("newpatient@test.com"), anyString());
        }

        @Test
        @DisplayName("registerPatient_withCaregiverId_shouldCreateLink")
        void registerPatient_withCaregiverId_shouldCreateLink() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            reg.setEmail("newpatient@test.com");
            reg.setFirstName("New");
            reg.setLastName("Patient");
            reg.setPhone("1234567890");
            reg.setDob("1990-01-01");
            reg.setAddress(new AddressDto("123 Main St", null, "City", "MD", "21001", null));
            reg.setCaregiverId(10L);

            when(users.existsByEmail("newpatient@test.com")).thenReturn(false);
            when(encoder.encode(anyString())).thenReturn("encodedPassword");
            when(users.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(5L);
                return u;
            });
            when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> {
                final Patient p = inv.getArgument(0);
                p.setId(25L);
                return p;
            });
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));

            final Patient result = caregiverService.registerPatient(reg);

            assertNotNull(result);
            verify(caregiverPatientLinkService).createPermanentLink(
                    eq(1L), eq(5L), eq("Patient registered by caregiver"));
        }

        @Test
        @DisplayName("registerPatient_emailAlreadyRegistered_shouldThrowRegistrationException")
        void registerPatient_emailAlreadyRegistered_shouldThrowRegistrationException() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            reg.setEmail("existing@test.com");

            when(users.existsByEmail("existing@test.com")).thenReturn(true);

            assertThrows(RegistrationException.class, () -> caregiverService.registerPatient(reg));
        }

        @Test
        @DisplayName("registerPatient_withNullAddress_shouldHandleGracefully")
        void registerPatient_withNullAddress_shouldHandleGracefully() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            reg.setEmail("newpatient@test.com");
            reg.setFirstName("New");
            reg.setLastName("Patient");
            reg.setPhone("1234567890");
            reg.setDob("1990-01-01");
            reg.setAddress(null);

            when(users.existsByEmail("newpatient@test.com")).thenReturn(false);
            when(encoder.encode(anyString())).thenReturn("encodedPassword");
            when(users.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(5L);
                return u;
            });
            when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> {
                final Patient p = inv.getArgument(0);
                p.setId(25L);
                return p;
            });

            final Patient result = caregiverService.registerPatient(reg);

            assertNotNull(result);
        }

        @Test
        @DisplayName("registerPatient_caregiverNotFound_shouldThrowAppException")
        void registerPatient_caregiverNotFound_shouldThrowAppException() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            reg.setEmail("newpatient@test.com");
            reg.setFirstName("New");
            reg.setLastName("Patient");
            reg.setCaregiverId(999L);

            when(users.existsByEmail("newpatient@test.com")).thenReturn(false);
            when(encoder.encode(anyString())).thenReturn("encodedPassword");
            when(users.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(5L);
                return u;
            });
            when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> {
                final Patient p = inv.getArgument(0);
                p.setId(25L);
                return p;
            });
            when(caregiverRepository.findById(999L)).thenReturn(Optional.empty());

            assertThrows(AppException.class, () -> caregiverService.registerPatient(reg));
        }

        @Test
        @DisplayName("registerPatient_linkCreationFails_shouldThrowAppException")
        void registerPatient_linkCreationFails_shouldThrowAppException() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            reg.setEmail("newpatient@test.com");
            reg.setFirstName("New");
            reg.setLastName("Patient");
            reg.setCaregiverId(10L);

            when(users.existsByEmail("newpatient@test.com")).thenReturn(false);
            when(encoder.encode(anyString())).thenReturn("encodedPassword");
            when(users.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(5L);
                return u;
            });
            when(patientRepository.save(any(Patient.class))).thenAnswer(inv -> {
                final Patient p = inv.getArgument(0);
                p.setId(25L);
                return p;
            });
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            doThrow(new RuntimeException("Link creation failed"))
                    .when(caregiverPatientLinkService).createPermanentLink(anyLong(), anyLong(), anyString());

            assertThrows(AppException.class, () -> caregiverService.registerPatient(reg));
        }

        @Test
        @DisplayName("registerPatient_databaseSaveFailure_shouldThrowAppException")
        void registerPatient_databaseSaveFailure_shouldThrowAppException() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            reg.setEmail("newpatient@test.com");
            reg.setFirstName("New");
            reg.setLastName("Patient");
            reg.setPhone("1234567890");
            reg.setDob("1990-01-01");
            reg.setAddress(new AddressDto("123 Main St", null, "City", "MD", "21001", null));

            when(users.existsByEmail("newpatient@test.com")).thenReturn(false);
            when(encoder.encode(anyString())).thenReturn("encodedPassword");
            when(users.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(5L);
                return u;
            });
            when(patientRepository.save(any(Patient.class)))
                    .thenThrow(new RuntimeException("DB error"));

            assertThrows(AppException.class, () -> caregiverService.registerPatient(reg));
        }
    }

    // ==================== registerCaregiver Tests ====================

    @Nested
    @DisplayName("registerCaregiver tests")
    class RegisterCaregiverTests {

        private CaregiverRegistration createValidCaregiverReg() throws Exception {
            final CaregiverRegistration reg = new CaregiverRegistration();
            reg.setFirstName("New");
            reg.setLastName("Caregiver");
            reg.setDob("1985-05-15");
            reg.setPhone("5555555555");
            reg.setAddress(new AddressDto("456 Elm St", null, "Town", "VA", "22001", null));
            reg.setCaregiverType("PROFESSIONAL");

            final LoginRequest credentials = new LoginRequest();
            credentials.setEmail("newcaregiver@test.com");
            credentials.setPassword("password123");
            reg.setCredentials(credentials);

            final ProfessionalInfoDto profDto = new ProfessionalInfoDto();
            profDto.setLicenseNumber("LIC123");
            profDto.setIssuingState("MD");
            profDto.setYearsExperience(5);
            reg.setProfessional(profDto);

            return reg;
        }

        @Test
        @DisplayName("registerCaregiver_validData_shouldCreateCaregiverWithStripe")
        void registerCaregiver_validData_shouldCreateCaregiverWithStripe() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("id", "cus_test123", "success", true));
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });

            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
            verify(caregiverRepository).save(any(Caregiver.class));
        }

        @Test
        @DisplayName("registerCaregiver_withPlanId_shouldCreateSubscription")
        void registerCaregiver_withPlanId_shouldCreateSubscription() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();
            reg.setPlanId("1");

            final Plan plan = new Plan();
            plan.setId(1L);
            plan.setCode("price_basic");

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("id", "cus_test123", "success", true));
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });
            when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
            when(stripeService.createSubscription("cus_test123", "price_basic"))
                    .thenReturn(Map.of("id", "sub_test123", "success", true));

            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
            verify(subscriptionRepository).save(any(Subscription.class));
        }

        @Test
        @DisplayName("registerCaregiver_emailAlreadyRegistered_shouldThrowRegistrationException")
        void registerCaregiver_emailAlreadyRegistered_shouldThrowRegistrationException() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(true);

            assertThrows(RegistrationException.class, () -> caregiverService.registerCaregiver(reg));
        }

        @Test
        @DisplayName("registerCaregiver_nullCaregiverType_shouldDefaultToProfessional")
        void registerCaregiver_nullCaregiverType_shouldDefaultToProfessional() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();
            reg.setCaregiverType(null);

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("id", "cus_test123", "success", true));
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });

            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
        }

        @Test
        @DisplayName("registerCaregiver_blankCaregiverType_shouldDefaultToProfessional")
        void registerCaregiver_blankCaregiverType_shouldDefaultToProfessional() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();
            reg.setCaregiverType("  ");

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("id", "cus_test123", "success", true));
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });

            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
        }

        @Test
        @DisplayName("registerCaregiver_nullStripeService_shouldUseMock")
        void registerCaregiver_nullStripeService_shouldUseMock() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();

            // Set stripeService to null to test mock path
            org.springframework.test.util.ReflectionTestUtils.setField(caregiverService, "stripeService", null);

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });

            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
        }

        @Test
        @DisplayName("registerCaregiver_stripeCreateCustomerFails_shouldThrowAppException")
        void registerCaregiver_stripeCreateCustomerFails_shouldThrowAppException() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(stripeService.createCustomer(anyString(), anyString()))
                    .thenThrow(new RuntimeException("Stripe error"));

            assertThrows(AppException.class, () -> caregiverService.registerCaregiver(reg));
        }

        @Test
        @DisplayName("registerCaregiver_stripeReturnsNullId_shouldThrowAppException")
        void registerCaregiver_stripeReturnsNullId_shouldThrowAppException() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("success", true));

            assertThrows(AppException.class, () -> caregiverService.registerCaregiver(reg));
        }

        @Test
        @DisplayName("registerCaregiver_databaseSaveFails_shouldThrowAppException")
        void registerCaregiver_databaseSaveFails_shouldThrowAppException() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("id", "cus_test123", "success", true));
            when(caregiverRepository.save(any(Caregiver.class)))
                    .thenThrow(new RuntimeException("DB error"));

            assertThrows(AppException.class, () -> caregiverService.registerCaregiver(reg));
        }

        @Test
        @DisplayName("registerCaregiver_nullProfessionalInfo_shouldHandleGracefully")
        void registerCaregiver_nullProfessionalInfo_shouldHandleGracefully() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();
            reg.setProfessional(null);

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("id", "cus_test123", "success", true));
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });

            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
        }

        @Test
        @DisplayName("registerCaregiver_subscriptionCreationFails_shouldStillSucceed")
        void registerCaregiver_subscriptionCreationFails_shouldStillSucceed() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();
            reg.setPlanId("1");

            final Plan plan = new Plan();
            plan.setId(1L);
            plan.setCode("price_basic");

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(stripeService.createCustomer("New Caregiver", "newcaregiver@test.com"))
                    .thenReturn(Map.of("id", "cus_test123", "success", true));
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });
            when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
            when(stripeService.createSubscription("cus_test123", "price_basic"))
                    .thenThrow(new RuntimeException("Stripe subscription error"));

            // Should still succeed even when subscription creation fails
            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
        }

        @Test
        @DisplayName("registerCaregiver_withPlanAndNullStripeService_shouldUseMockSubscription")
        void registerCaregiver_withPlanAndNullStripeService_shouldUseMockSubscription() throws Exception {
            final CaregiverRegistration reg = createValidCaregiverReg();
            reg.setPlanId("1");

            org.springframework.test.util.ReflectionTestUtils.setField(caregiverService, "stripeService", null);

            final Plan plan = new Plan();
            plan.setId(1L);
            plan.setCode("price_basic");

            when(users.existsByEmail("newcaregiver@test.com")).thenReturn(false);
            when(encoder.encode("password123")).thenReturn("encodedPassword");
            when(caregiverRepository.save(any(Caregiver.class))).thenAnswer(inv -> {
                final Caregiver c = inv.getArgument(0);
                c.setId(15L);
                return c;
            });
            when(planRepository.findById(1L)).thenReturn(Optional.of(plan));

            final Caregiver result = caregiverService.registerCaregiver(reg);

            assertNotNull(result);
            verify(subscriptionRepository).save(any(Subscription.class));
        }
    }

    // ==================== hasAccessToPatient Tests ====================

    @Nested
    @DisplayName("hasAccessToPatient tests")
    class HasAccessToPatientTests {

        @Test
        @DisplayName("hasAccessToPatient_patientRole_ownData_shouldReturnTrue")
        void hasAccessToPatient_patientRole_ownData_shouldReturnTrue() throws Exception {
            when(users.findById(2L)).thenReturn(Optional.of(patientUser));
            when(patientRepository.existsByIdAndUserId(20L, 2L)).thenReturn(true);

            assertTrue(caregiverService.hasAccessToPatient(2L, 20L));
        }

        @Test
        @DisplayName("hasAccessToPatient_patientRole_otherData_shouldReturnFalse")
        void hasAccessToPatient_patientRole_otherData_shouldReturnFalse() throws Exception {
            when(users.findById(2L)).thenReturn(Optional.of(patientUser));
            when(patientRepository.existsByIdAndUserId(30L, 2L)).thenReturn(false);

            assertFalse(caregiverService.hasAccessToPatient(2L, 30L));
        }

        @Test
        @DisplayName("hasAccessToPatient_caregiverRole_withAccess_shouldReturnTrue")
        void hasAccessToPatient_caregiverRole_withAccess_shouldReturnTrue() throws Exception {
            when(users.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(patientRepository.hasAccessByCaregiverId(20L, 1L)).thenReturn(true);

            assertTrue(caregiverService.hasAccessToPatient(1L, 20L));
        }

        @Test
        @DisplayName("hasAccessToPatient_caregiverRole_withoutAccess_shouldReturnFalse")
        void hasAccessToPatient_caregiverRole_withoutAccess_shouldReturnFalse() throws Exception {
            when(users.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(patientRepository.hasAccessByCaregiverId(20L, 1L)).thenReturn(false);

            assertFalse(caregiverService.hasAccessToPatient(1L, 20L));
        }

        @Test
        @DisplayName("hasAccessToPatient_familyMemberRole_shouldCheckFamilyMemberLink")
        void hasAccessToPatient_familyMemberRole_shouldCheckFamilyMemberLink() throws Exception {
            final User fmUser = new User();
            fmUser.setId(3L);
            fmUser.setRole(Role.FAMILY_MEMBER);

            final User patientUser = new User();
            patientUser.setId(77L);
            final Patient patient = new Patient();
            patient.setId(20L);
            patient.setUser(patientUser);

            when(users.findById(3L)).thenReturn(Optional.of(fmUser));
            when(patientRepository.findById(20L)).thenReturn(Optional.of(patient));
            when(familyMemberLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    eq(3L), eq(77L), any(LocalDateTime.class))).thenReturn(true);

            assertTrue(caregiverService.hasAccessToPatient(3L, 20L));
        }

        @Test
        @DisplayName("hasAccessToPatient_familyMemberRole_unknownPatient_shouldDeny")
        void hasAccessToPatient_familyMemberRole_unknownPatient_shouldDeny() throws Exception {
            final User fmUser = new User();
            fmUser.setId(3L);
            fmUser.setRole(Role.FAMILY_MEMBER);

            when(users.findById(3L)).thenReturn(Optional.of(fmUser));
            when(patientRepository.findById(404L)).thenReturn(Optional.empty());

            assertFalse(caregiverService.hasAccessToPatient(3L, 404L));
            verifyNoInteractions(familyMemberLinkRepository);
        }

        @Test
        @DisplayName("hasAccessToPatient_adminRole_shouldAlwaysReturnTrue")
        void hasAccessToPatient_adminRole_shouldAlwaysReturnTrue() throws Exception {
            final User adminUser = new User();
            adminUser.setId(4L);
            adminUser.setRole(Role.ADMIN);

            when(users.findById(4L)).thenReturn(Optional.of(adminUser));

            assertTrue(caregiverService.hasAccessToPatient(4L, 20L));
        }

        @Test
        @DisplayName("hasAccessToPatient_userNotFound_shouldReturnFalse")
        void hasAccessToPatient_userNotFound_shouldReturnFalse() throws Exception {
            when(users.findById(999L)).thenReturn(Optional.empty());

            assertFalse(caregiverService.hasAccessToPatient(999L, 20L));
        }
    }

    // ==================== caregiverHasAccessToPatient Tests ====================

    @Nested
    @DisplayName("caregiverHasAccessToPatient tests")
    class CaregiverHasAccessToPatientTests {

        @Test
        @DisplayName("caregiverHasAccessToPatient_validLink_shouldReturnTrue")
        void caregiverHasAccessToPatient_validLink_shouldReturnTrue() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(patientRepository.findById(20L)).thenReturn(Optional.of(testPatient));
            when(caregiverPatientLinkService.hasAccessToPatient(1L, 2L)).thenReturn(true);

            assertTrue(caregiverService.caregiverHasAccessToPatient(10L, 20L));
        }

        @Test
        @DisplayName("caregiverHasAccessToPatient_noLink_shouldReturnFalse")
        void caregiverHasAccessToPatient_noLink_shouldReturnFalse() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(patientRepository.findById(20L)).thenReturn(Optional.of(testPatient));
            when(caregiverPatientLinkService.hasAccessToPatient(1L, 2L)).thenReturn(false);

            assertFalse(caregiverService.caregiverHasAccessToPatient(10L, 20L));
        }

        @Test
        @DisplayName("caregiverHasAccessToPatient_caregiverNotFound_shouldReturnFalse")
        void caregiverHasAccessToPatient_caregiverNotFound_shouldReturnFalse() throws Exception {
            when(caregiverRepository.findById(999L)).thenReturn(Optional.empty());

            assertFalse(caregiverService.caregiverHasAccessToPatient(999L, 20L));
        }

        @Test
        @DisplayName("caregiverHasAccessToPatient_patientNotFound_shouldReturnFalse")
        void caregiverHasAccessToPatient_patientNotFound_shouldReturnFalse() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(patientRepository.findById(999L)).thenReturn(Optional.empty());

            assertFalse(caregiverService.caregiverHasAccessToPatient(10L, 999L));
        }
    }

    // ==================== getPatientWithLinkById Tests ====================

    @Nested
    @DisplayName("getPatientWithLinkById tests")
    class GetPatientWithLinkByIdTests {

        @Test
        @DisplayName("getPatientWithLinkById_validLink_shouldReturnPatientWithLink")
        void getPatientWithLinkById_validLink_shouldReturnPatientWithLink() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(patientRepository.findById(20L)).thenReturn(Optional.of(testPatient));

            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    2L, "John Doe", "patient@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));
            when(patientRiskService.getFlaggedRisksForPatient(20L))
                    .thenReturn(List.of());

            final PatientWithLinkDto result = caregiverService.getPatientWithLinkById(10L, 20L);

            assertNotNull(result);
            assertEquals("John", result.patient().firstName());
            assertEquals("Doe", result.patient().lastName());
        }

        @Test
        @DisplayName("getPatientWithLinkById_patientNotFound_shouldThrowAppException")
        void getPatientWithLinkById_patientNotFound_shouldThrowAppException() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(patientRepository.findById(999L)).thenReturn(Optional.empty());

            assertThrows(AppException.class,
                    () -> caregiverService.getPatientWithLinkById(10L, 999L));
        }

        @Test
        @DisplayName("getPatientWithLinkById_noActiveLink_shouldThrowAppException")
        void getPatientWithLinkById_noActiveLink_shouldThrowAppException() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(patientRepository.findById(20L)).thenReturn(Optional.of(testPatient));
            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of());

            assertThrows(AppException.class,
                    () -> caregiverService.getPatientWithLinkById(10L, 20L));
        }

        @Test
        @DisplayName("getPatientWithLinkById_linkForDifferentPatient_shouldThrowAppException")
        void getPatientWithLinkById_linkForDifferentPatient_shouldThrowAppException() throws Exception {
            when(caregiverRepository.findById(10L)).thenReturn(Optional.of(testCaregiver));
            when(patientRepository.findById(20L)).thenReturn(Optional.of(testPatient));

            // Link is for a different patient user ID
            final CaregiverPatientLinkResponse linkResponse = new CaregiverPatientLinkResponse(
                    1L, 1L, "Jane Smith", "caregiver@test.com",
                    99L, "Other Patient", "other@test.com",
                    "ACTIVE", "PERMANENT", false, false, LocalDateTime.now(), null,
                    "", "Test", true, false
            );

            when(caregiverPatientLinkService.getPatientsByCaregiver(1L))
                    .thenReturn(List.of(linkResponse));

            assertThrows(AppException.class,
                    () -> caregiverService.getPatientWithLinkById(10L, 20L));
        }
    }
}
