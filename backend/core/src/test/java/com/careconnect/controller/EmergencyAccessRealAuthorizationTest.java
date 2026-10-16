package com.careconnect.controller;

import com.careconnect.config.SecurityConfig;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.Patient;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.careconnect.security.UserDetailsServiceImpl;
import com.careconnect.service.PatientService;
import com.careconnect.service.VialOfLifePdfService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan.Filter;
import org.springframework.context.annotation.FilterType;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpHeaders;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PR #336 (DEF-EMG-01 / DEF-EMG-03 interim fix) with the real access decision: the real {@link SecurityConfig}
 * chain, the real {@link SecurityUtil} (HTTP Basic principal to the user record) and the real
 * {@link AuthorizationService#requirePatientAccess}. Only the stores are mocked: the user lookup, the
 * caregiver and family-member link queries, the patient lookup and the PDF service.
 *
 * <p>EmergencyAccessControlTest and EmergencyControllerTest mock the caller and the access check, so neither
 * shows that a linked caregiver or family member really gets the PDF, or that the link queries are asked
 * about the patient's user id rather than the record id in {@code VIAL<record id>}.
 *
 * <p>Patient record 1 belongs to user 100. Every account and password is synthetic.
 *
 * <p>Test Plan §3.22: TC-EMG-198…206 (Testing Lead). Test IDs are permanent.
 */
@WebMvcTest(controllers = EmergencyController.class,
        excludeFilters = @Filter(type = FilterType.ASSIGNABLE_TYPE, classes = GlobalExceptionHandler.class))
@Import({SecurityConfig.class, SecurityUtil.class, AuthorizationService.class,
        EmergencyAccessRealAuthorizationTest.TestConfig.class})
class EmergencyAccessRealAuthorizationTest {

    private static final String PASSWORD = "synthetic-test-password";
    private static final String PDF = "/v1/api/emergency/VIAL1.pdf";
    private static final String DOWNLOAD = "/v1/api/emergency/download/VIAL1.pdf";
    private static final long PATIENT_ONE_RECORD = 1L;
    private static final long PATIENT_ONE_USER = 100L;
    private static final long LINKED_CAREGIVER = 300L;
    private static final long LINKED_FAMILY = 400L;

    /** email -> (user id, role) for every synthetic account. */
    private static final Map<String, Object[]> ACCOUNTS = Map.of(
            "patient-one@test.invalid", new Object[]{PATIENT_ONE_USER, Role.PATIENT},
            "other-patient@test.invalid", new Object[]{200L, Role.PATIENT},
            "linked-caregiver@test.invalid", new Object[]{LINKED_CAREGIVER, Role.CAREGIVER},
            "unlinked-caregiver@test.invalid", new Object[]{301L, Role.CAREGIVER},
            "linked-family@test.invalid", new Object[]{LINKED_FAMILY, Role.FAMILY_MEMBER},
            "unlinked-family@test.invalid", new Object[]{401L, Role.FAMILY_MEMBER},
            "admin@test.invalid", new Object[]{1L, Role.ADMIN});

    @Autowired
    MockMvc mvc;
    @Autowired
    PasswordEncoder passwordEncoder;

    @MockitoBean
    JwtTokenProvider jwtTokenProvider;
    @MockitoBean
    UserDetailsServiceImpl userDetailsService;
    @MockitoBean
    UserRepository userRepository;
    @MockitoBean
    CaregiverPatientLinkRepository caregiverLinks;
    @MockitoBean
    FamilyMemberLinkRepository familyLinks;
    @MockitoBean
    PatientService patientService;
    @MockitoBean
    VialOfLifePdfService vialOfLifePdfService;

    @BeforeEach
    void setUp() throws Exception {
        reset(userDetailsService, userRepository, caregiverLinks, familyLinks, patientService, vialOfLifePdfService);
        lenient().when(vialOfLifePdfService.generateVialOfLifePdf(anyString()))
                .thenReturn("%PDF-synthetic".getBytes(StandardCharsets.US_ASCII));

        final Patient patientOne = new Patient();
        patientOne.setId(PATIENT_ONE_RECORD);
        patientOne.setUser(com.careconnect.model.User.builder().id(PATIENT_ONE_USER).role(Role.PATIENT).build());
        lenient().when(patientService.getPatientById(PATIENT_ONE_RECORD)).thenReturn(patientOne);

        for (final Map.Entry<String, Object[]> account : ACCOUNTS.entrySet()) {
            final String email = account.getKey();
            final Role role = (Role) account.getValue()[1];
            // A fresh UserDetails per lookup: Spring erases the credentials of the instance it authenticated.
            lenient().when(userDetailsService.loadUserByUsername(email)).thenAnswer(inv ->
                    org.springframework.security.core.userdetails.User.withUsername(email)
                            .password(passwordEncoder.encode(PASSWORD)).roles(role.name()).build());
            lenient().when(userRepository.findByEmailAndRole(email, role)).thenReturn(Optional.of(
                    com.careconnect.model.User.builder().id((Long) account.getValue()[0]).email(email).role(role).build()));
        }
        // The only active links to patient 1 are keyed by user ids, as the repositories store them.
        lenient().when(caregiverLinks.existsActiveNonExpiredLinkByUserIds(eq(LINKED_CAREGIVER), eq(PATIENT_ONE_USER), any()))
                .thenReturn(true);
        lenient().when(familyLinks.existsActiveNonExpiredLinkByUserIds(eq(LINKED_FAMILY), eq(PATIENT_ONE_USER), any()))
                .thenReturn(true);
    }

    private static MockHttpServletRequestBuilder as(final String email, final String path) {
        final String credentials = Base64.getEncoder()
                .encodeToString((email + ":" + PASSWORD).getBytes(StandardCharsets.UTF_8));
        return get(path).header(HttpHeaders.AUTHORIZATION, "Basic " + credentials);
    }

    private void getsBothPdfs(final String email) throws Exception {
        mvc.perform(as(email, PDF)).andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(as(email, DOWNLOAD)).andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        verify(vialOfLifePdfService, times(2)).generateVialOfLifePdf("VIAL1");
    }

    @Test
    @DisplayName("TC-EMG-198: patient 1's own account gets their PDF from both paths")
    void ownerGetsThePdf() throws Exception {
        getsBothPdfs("patient-one@test.invalid");
    }

    @Test
    @DisplayName("TC-EMG-199: a caregiver with an active link to patient 1 gets the PDF from both paths, and the link "
            + "is looked up by the caregiver's and the patient's user ids, not the record id")
    void linkedCaregiverGetsThePdf() throws Exception {
        getsBothPdfs("linked-caregiver@test.invalid");
        verify(caregiverLinks, times(2)).existsActiveNonExpiredLinkByUserIds(eq(LINKED_CAREGIVER), eq(PATIENT_ONE_USER), any());
        verify(caregiverLinks, never()).existsActiveNonExpiredLinkByUserIds(anyLong(), eq(PATIENT_ONE_RECORD), any());
    }

    @Test
    @DisplayName("TC-EMG-200: a family member with an active link to patient 1 gets the PDF from both paths, looked up "
            + "by user ids")
    void linkedFamilyMemberGetsThePdf() throws Exception {
        getsBothPdfs("linked-family@test.invalid");
        verify(familyLinks, times(2)).existsActiveNonExpiredLinkByUserIds(eq(LINKED_FAMILY), eq(PATIENT_ONE_USER), any());
    }

    @Test
    @DisplayName("TC-EMG-201: an administrator gets patient 1's PDF from both paths")
    void adminGetsThePdf() throws Exception {
        getsBothPdfs("admin@test.invalid");
    }

    @ParameterizedTest(name = "{0}: {1} is refused patient 1's PDF with 404 on both paths and nothing is generated")
    @CsvSource({
            "TC-EMG-202, other-patient@test.invalid",
            "TC-EMG-203, unlinked-caregiver@test.invalid",
            "TC-EMG-204, unlinked-family@test.invalid"})
    void unrelatedAccountIsRefused(final String id, final String email) throws Exception {
        mvc.perform(as(email, PDF)).andExpect(status().isNotFound());
        mvc.perform(as(email, DOWNLOAD)).andExpect(status().isNotFound());
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    @Test
    @DisplayName("TC-EMG-205: an administrator still gets the debug endpoint's answer")
    void adminGetsDebug() throws Exception {
        mvc.perform(as("admin@test.invalid", "/v1/api/emergency/debug/VIAL1"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.startsWith("SUCCESS")));
    }

    @Test
    @DisplayName("TC-EMG-206: the debug endpoint is 404 even for a caregiver linked to the patient, and nothing is generated")
    void linkedCaregiverIsRefusedDebug() throws Exception {
        mvc.perform(as("linked-caregiver@test.invalid", "/v1/api/emergency/debug/VIAL1"))
                .andExpect(status().isNotFound());
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    /** A concrete CORS source, as in SecurityConfigFilterChainTest, so the MVC introspector bean survives. */
    @TestConfiguration
    static class TestConfig {
        @Bean
        @Primary
        CorsConfigurationSource testCorsConfigurationSource() {
            final CorsConfiguration cfg = new CorsConfiguration();
            cfg.setAllowedOrigins(List.of("*"));
            cfg.setAllowedMethods(List.of("*"));
            cfg.setAllowedHeaders(List.of("*"));
            final UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
            source.registerCorsConfiguration("/**", cfg);
            return source;
        }
    }
}
