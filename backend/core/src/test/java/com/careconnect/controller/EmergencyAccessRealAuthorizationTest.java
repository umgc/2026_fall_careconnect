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
import io.jsonwebtoken.Claims;
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
import jakarta.servlet.http.Cookie;
import org.springframework.http.HttpHeaders;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
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
 *
 * <p>PR #343 (DEF-EMG-02): the same decision for callers who sign in with a token, as the app does, through the
 * real {@code JwtAuthenticationFilter}. Test Plan §3.29: TC-EMG-424…429 (PR author), 430…439 (Testing Lead).
 * 435…439 hand the provider's checks to a real {@link JwtTokenProvider} with a random synthetic key, so real
 * tokens are signed, expired and tampered with.
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
        // A sign-in left on the thread by an earlier test class would reach BasicAuthenticationFilter (PR #343 CI).
        SecurityContextHolder.clearContext();
        reset(jwtTokenProvider, userDetailsService, userRepository, caregiverLinks, familyLinks, patientService,
                vialOfLifePdfService);
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

    // DEF-EMG-02 (PR #343): the app signs in with a token, not Basic auth.

    /** A sign-in token for {@code email}, which the mocked provider accepts as JwtAuthenticationFilter checks it. */
    private String tokenFor(final String email) {
        final Object[] account = ACCOUNTS.get(email);
        final String role = ((Role) account[1]).name();
        final String token = "synthetic-token-" + account[0];
        final Claims claims = mock(Claims.class);
        lenient().when(claims.getSubject()).thenReturn(email);
        lenient().when(claims.get("role", String.class)).thenReturn(role);
        lenient().when(jwtTokenProvider.validateToken(token)).thenReturn(true);
        lenient().when(jwtTokenProvider.getClaims(token)).thenReturn(claims);
        tokenAccount(email);
        return token;
    }

    /** The account the filter loads for a token's subject and role claim. */
    private void tokenAccount(final String email) {
        final String role = ((Role) ACCOUNTS.get(email)[1]).name();
        lenient().when(userDetailsService.loadUserByEmailAndRole(email, role)).thenAnswer(inv ->
                org.springframework.security.core.userdetails.User.withUsername(email)
                        .password("n/a").roles(role).build());
    }

    private MockHttpServletRequestBuilder withToken(final String email, final String path) {
        return get(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + tokenFor(email));
    }

    private MockHttpServletRequestBuilder withCookie(final String email, final String path) {
        return get(path).cookie(new Cookie("AUTH", tokenFor(email)));
    }

    @Test
    @DisplayName("TC-EMG-424: DEF-EMG-02: patient 1's own sign-in token gets their PDF from both paths")
    void patientsOwnTokenGetsThePdf() throws Exception {
        mvc.perform(withToken("patient-one@test.invalid", PDF))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(withToken("patient-one@test.invalid", DOWNLOAD))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        verify(vialOfLifePdfService, times(2)).generateVialOfLifePdf("VIAL1");
    }

    @Test
    @DisplayName("TC-EMG-425: DEF-EMG-02: a caregiver linked to patient 1 gets the PDF from both paths with their "
            + "sign-in token, the link looked up by user ids")
    void linkedCaregiversTokenGetsThePdf() throws Exception {
        mvc.perform(withToken("linked-caregiver@test.invalid", PDF))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(withToken("linked-caregiver@test.invalid", DOWNLOAD))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        verify(vialOfLifePdfService, times(2)).generateVialOfLifePdf("VIAL1");
        verify(caregiverLinks, times(2)).existsActiveNonExpiredLinkByUserIds(eq(LINKED_CAREGIVER), eq(PATIENT_ONE_USER), any());
    }

    @ParameterizedTest(name = "{0}: DEF-EMG-02: {1}'s sign-in token is refused patient 1's PDF with 404 on both paths and nothing is generated")
    @CsvSource({
            "TC-EMG-426, other-patient@test.invalid",
            "TC-EMG-427, unlinked-caregiver@test.invalid",
            "TC-EMG-428, unlinked-family@test.invalid"})
    void unrelatedTokenIsRefused(final String id, final String email) throws Exception {
        mvc.perform(withToken(email, PDF)).andExpect(status().isNotFound());
        mvc.perform(withToken(email, DOWNLOAD)).andExpect(status().isNotFound());
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    @Test
    @DisplayName("TC-EMG-429: DEF-EMG-02: the debug endpoint stays 404 for a linked caregiver's sign-in token")
    void linkedCaregiversTokenIsRefusedDebug() throws Exception {
        mvc.perform(withToken("linked-caregiver@test.invalid", "/v1/api/emergency/debug/VIAL1"))
                .andExpect(status().isNotFound());
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    @Test
    @DisplayName("TC-EMG-430: DEF-EMG-02: a family member linked to patient 1 gets the PDF from both paths with their "
            + "sign-in token, the link looked up by user ids")
    void linkedFamilyMembersTokenGetsThePdf() throws Exception {
        mvc.perform(withToken("linked-family@test.invalid", PDF))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(withToken("linked-family@test.invalid", DOWNLOAD))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        verify(vialOfLifePdfService, times(2)).generateVialOfLifePdf("VIAL1");
        verify(familyLinks, times(2)).existsActiveNonExpiredLinkByUserIds(eq(LINKED_FAMILY), eq(PATIENT_ONE_USER), any());
    }

    @Test
    @DisplayName("TC-EMG-431: DEF-EMG-02: an administrator's sign-in token gets patient 1's PDF from both paths and the "
            + "debug endpoint's answer")
    void adminsTokenGetsThePdfAndDebug() throws Exception {
        mvc.perform(withToken("admin@test.invalid", PDF))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(withToken("admin@test.invalid", DOWNLOAD))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(withToken("admin@test.invalid", "/v1/api/emergency/debug/VIAL1"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.startsWith("SUCCESS")));
    }

    @Test
    @DisplayName("TC-EMG-432: DEF-EMG-02: patient 1's own sign-in cookie (AUTH) gets their PDF from both paths")
    void patientsOwnCookieGetsThePdf() throws Exception {
        mvc.perform(withCookie("patient-one@test.invalid", PDF))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(withCookie("patient-one@test.invalid", DOWNLOAD))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        verify(vialOfLifePdfService, times(2)).generateVialOfLifePdf("VIAL1");
    }

    @Test
    @DisplayName("TC-EMG-433: DEF-EMG-02: another patient's sign-in cookie (AUTH) is refused patient 1's PDF with 404 on "
            + "both paths and nothing is generated")
    void otherPatientsCookieIsRefused() throws Exception {
        mvc.perform(withCookie("other-patient@test.invalid", PDF)).andExpect(status().isNotFound());
        mvc.perform(withCookie("other-patient@test.invalid", DOWNLOAD)).andExpect(status().isNotFound());
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    @Test
    @DisplayName("TC-EMG-434: DEF-EMG-02: with a sign-in token, a refusal, an unknown patient and a malformed ID get the "
            + "same 404 (status, headers and body)")
    void tokenRefusalLooksLikeAnUnknownId() throws Exception {
        final MvcResult refused = mvc.perform(withToken("other-patient@test.invalid", PDF)).andReturn();
        final MvcResult unknown = mvc.perform(withToken("other-patient@test.invalid", "/v1/api/emergency/VIAL999.pdf")).andReturn();
        final MvcResult malformed = mvc.perform(withToken("other-patient@test.invalid", "/v1/api/emergency/ABC1.pdf")).andReturn();
        assertEquals(404, refused.getResponse().getStatus());
        for (final MvcResult other : List.of(unknown, malformed)) {
            assertEquals(refused.getResponse().getStatus(), other.getResponse().getStatus());
            assertEquals(refused.getResponse().getHeaderNames(), other.getResponse().getHeaderNames());
            for (final String header : refused.getResponse().getHeaderNames()) {
                assertEquals(refused.getResponse().getHeaders(header), other.getResponse().getHeaders(header), header);
            }
            assertArrayEquals(refused.getResponse().getContentAsByteArray(), other.getResponse().getContentAsByteArray());
        }
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    // 435…439: real tokens. The provider's checks go to a real JwtTokenProvider; the key is random and synthetic.

    private static String randomKey() {
        final byte[] key = new byte[32];
        new SecureRandom().nextBytes(key);
        return Base64.getEncoder().encodeToString(key);
    }

    /** Hands the filter's token checks to {@code real}, and loads every account a token may name. */
    private void realTokensFrom(final JwtTokenProvider real) {
        when(jwtTokenProvider.validateToken(anyString())).thenAnswer(inv -> real.validateToken(inv.getArgument(0)));
        when(jwtTokenProvider.getClaims(anyString())).thenAnswer(inv -> real.getClaims(inv.getArgument(0)));
        when(jwtTokenProvider.needsRenewal(any())).thenAnswer(inv -> real.needsRenewal(inv.getArgument(0)));
        ACCOUNTS.keySet().forEach(this::tokenAccount);
    }

    private void refusedWith401(final String token) throws Exception {
        mvc.perform(get(PDF).header(HttpHeaders.AUTHORIZATION, "Bearer " + token)).andExpect(status().isUnauthorized());
        mvc.perform(get(DOWNLOAD).cookie(new Cookie("AUTH", token))).andExpect(status().isUnauthorized());
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    @Test
    @DisplayName("TC-EMG-435: DEF-EMG-02: a real signed token for patient 1 gets their PDF, as a header and as the AUTH cookie")
    void realTokenGetsThePdf() throws Exception {
        final JwtTokenProvider real = new JwtTokenProvider(randomKey(), 600_000L);
        realTokensFrom(real);
        final String token = real.createToken("patient-one@test.invalid", Role.PATIENT);
        mvc.perform(get(PDF).header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        mvc.perform(get(DOWNLOAD).cookie(new Cookie("AUTH", token)))
                .andExpect(status().isOk()).andExpect(content().contentType("application/pdf"));
        verify(vialOfLifePdfService, times(2)).generateVialOfLifePdf("VIAL1");
    }

    @Test
    @DisplayName("TC-EMG-436: DEF-EMG-02: a real signed token for another patient is refused patient 1's PDF with 404 "
            + "on both paths and nothing is generated")
    void realTokenForAnotherPatientIsRefused() throws Exception {
        final JwtTokenProvider real = new JwtTokenProvider(randomKey(), 600_000L);
        realTokensFrom(real);
        final String token = real.createToken("other-patient@test.invalid", Role.PATIENT);
        mvc.perform(get(PDF).header(HttpHeaders.AUTHORIZATION, "Bearer " + token)).andExpect(status().isNotFound());
        mvc.perform(get(DOWNLOAD).cookie(new Cookie("AUTH", token))).andExpect(status().isNotFound());
        verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
    }

    @Test
    @DisplayName("TC-EMG-437: DEF-EMG-02: a token for patient 1 signed with another key is 401 and nothing is generated")
    void tokenSignedWithAnotherKeyIsRefused() throws Exception {
        realTokensFrom(new JwtTokenProvider(randomKey(), 600_000L));
        refusedWith401(new JwtTokenProvider(randomKey(), 600_000L).createToken("patient-one@test.invalid", Role.PATIENT));
    }

    @Test
    @DisplayName("TC-EMG-438: DEF-EMG-02: an expired token for patient 1 is 401 and nothing is generated")
    void expiredTokenIsRefused() throws Exception {
        final String key = randomKey();
        realTokensFrom(new JwtTokenProvider(key, 600_000L));
        refusedWith401(new JwtTokenProvider(key, -60_000L).createToken("patient-one@test.invalid", Role.PATIENT));
    }

    @Test
    @DisplayName("TC-EMG-439: DEF-EMG-02: another patient's token edited to name patient 1, signature kept, is 401 and "
            + "nothing is generated")
    void tamperedTokenIsRefused() throws Exception {
        final JwtTokenProvider real = new JwtTokenProvider(randomKey(), 600_000L);
        realTokensFrom(real);
        final String[] parts = real.createToken("other-patient@test.invalid", Role.PATIENT).split("\\.");
        final String payload = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8)
                .replace("other-patient@test.invalid", "patient-one@test.invalid");
        assertTrue(payload.contains("patient-one@test.invalid"));
        final String forged = parts[0] + "."
                + Base64.getUrlEncoder().withoutPadding().encodeToString(payload.getBytes(StandardCharsets.UTF_8))
                + "." + parts[2];
        refusedWith401(forged);
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
