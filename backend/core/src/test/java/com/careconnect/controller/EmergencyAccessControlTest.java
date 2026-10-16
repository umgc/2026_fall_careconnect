package com.careconnect.controller;

import com.careconnect.config.SecurityConfig;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.exception.AppException;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.UserDetailsServiceImpl;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.PatientService;
import com.careconnect.service.VialOfLifePdfService;
import com.careconnect.util.SecurityUtil;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
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
import org.springframework.http.HttpStatus;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import jakarta.servlet.http.Cookie;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * CR-1 (#299) Increment 0 for CC-12: who can reach the existing emergency endpoints today,
 * through the application's real {@link SecurityConfig} chain.
 *
 * <p>CR-1 requires that "signing in alone must not give someone access to another patient's
 * information" and that "nothing is public by default". These tests record where the current
 * {@code /v1/api/emergency/*} endpoints stand against that, before Increments 1-3 replace them:
 * <ul>
 *   <li>{@link AlreadySecure}: anonymous callers and unusable tokens are refused, and no PDF is
 *       generated. These are regression guards and must keep passing.</li>
 *   <li>{@link InterimFix}: DEF-EMG-01 and DEF-EMG-03 are fixed for now (PR #336): another account is
 *       refused the PDF with the same 404 as an unknown ID, the patient still gets it, and the debug
 *       endpoint is closed to a patient account. Regression guards until Increment 2 replaces the endpoints.</li>
 *   <li>{@link CurrentGaps}: characterization of DEF-EMG-02, still open. Each asserts today's
 *       behaviour, so it fails the day the gap is closed and must then be rewritten (or removed in
 *       favour of the matching {@link Target} case).</li>
 *   <li>{@link Target}: the required behaviour once DEF-EMG-02 is fixed, disabled until then.</li>
 * </ul>
 *
 * <p>The emergency ID is {@code "VIAL" + patient.id} (VialOfLifePdfService
 * #extractPatientIdFromEmergencyId), so it is guessable, and the PDF holds the patient's name,
 * date of birth, medications and family contacts. The caller and the access check are mocked here;
 * EmergencyAccessRealAuthorizationTest runs the real ones.
 *
 * <p>Test Plan IDs: TC-EMG-001...014, 148 and 197 (Test Plan section 3.22); 007 and 010 are withdrawn
 * (duplicates of 011 and 012 once the gaps closed). Defects: DEF-EMG-01 (GAP 1), DEF-EMG-02 (GAP 2) and
 * DEF-EMG-03 (GAP 3).
 */
@WebMvcTest(controllers = EmergencyController.class,
        excludeFilters = @Filter(type = FilterType.ASSIGNABLE_TYPE, classes = GlobalExceptionHandler.class))
@Import({SecurityConfig.class, EmergencyAccessControlTest.TestConfig.class})
class EmergencyAccessControlTest {

    private static final String PATIENT_ONE_PDF = "/v1/api/emergency/VIAL1.pdf";
    private static final String OTHER_USER = "other-patient@test.invalid";
    private static final String OTHER_USER_PASSWORD = "synthetic-test-password";
    private static final String VALID_TOKEN = "valid.synthetic.token";

    @Autowired
    MockMvc mvc;
    @Autowired
    PasswordEncoder passwordEncoder;

    @MockitoBean
    JwtTokenProvider jwtTokenProvider;
    @MockitoBean
    UserDetailsServiceImpl userDetailsService;
    @MockitoBean
    SecurityUtil securityUtil;
    @MockitoBean
    AuthorizationService authorizationService;
    @MockitoBean
    VialOfLifePdfService vialOfLifePdfService;
    @MockitoBean
    Claims claims;
    @MockitoBean
    PatientService patientService;

    /** Patient record 1 belongs to user 100. The "other patient" signing in below is user 200. */
    private static final long PATIENT_ONE_USER = 100L;

    @BeforeEach
    void setUp() throws Exception {
        // @MockitoBean mocks are not reset between the @Nested classes' tests, so earlier calls
        // would otherwise count against the never()/times() checks below, and a stub set by one test
        // (GAP 3's thenThrow) would stay in place for the next. Reset calls and stubs, then stub again.
        reset(vialOfLifePdfService, jwtTokenProvider, userDetailsService, claims, securityUtil, authorizationService, patientService);
        lenient().when(vialOfLifePdfService.generateVialOfLifePdf(anyString()))
                .thenReturn("%PDF-synthetic".getBytes(StandardCharsets.US_ASCII));

        // A different patient's account. A fresh UserDetails per lookup: Spring erases the
        // credentials of the instance it authenticated, so reusing one would fail later requests.
        lenient().when(userDetailsService.loadUserByUsername(OTHER_USER)).thenAnswer(inv ->
                User.withUsername(OTHER_USER).password(passwordEncoder.encode(OTHER_USER_PASSWORD))
                        .roles("PATIENT").build());
        lenient().when(userDetailsService.loadUserByEmailAndRole(anyString(), anyString())).thenAnswer(inv ->
                User.withUsername(OTHER_USER).password("n/a").roles("PATIENT").build());

        // DEF-EMG-01 interim fix: the controller resolves the caller and asks AuthorizationService.
        // Only patient 1's own user (100) passes; the signed-in caller here is another patient (200).
        final com.careconnect.model.Patient patientOne = new com.careconnect.model.Patient();
        patientOne.setId(1L);
        patientOne.setUser(com.careconnect.model.User.builder().id(PATIENT_ONE_USER).role(Role.PATIENT).build());
        lenient().when(patientService.getPatientById(1L)).thenReturn(patientOne);
        // As the real PatientService does for a record that does not exist.
        lenient().when(patientService.getPatientById(999L))
                .thenThrow(new AppException(HttpStatus.NOT_FOUND, "Patient not found"));
        lenient().when(securityUtil.resolveCurrentUser())
                .thenReturn(com.careconnect.model.User.builder().id(200L).role(Role.PATIENT).build());
        lenient().doAnswer(inv -> {
            final com.careconnect.model.User caller = inv.getArgument(0);
            if (caller == null || !Long.valueOf(PATIENT_ONE_USER).equals(caller.getId())) {
                throw new UnauthorizedException("refused");
            }
            return null;
        }).when(authorizationService).requirePatientAccess(any(), eq(PATIENT_ONE_USER));

        // A token the JWT filter would accept, if it ran on these paths.
        lenient().when(jwtTokenProvider.validateToken(VALID_TOKEN)).thenReturn(true);
        lenient().when(jwtTokenProvider.getClaims(VALID_TOKEN)).thenReturn(claims);
        lenient().when(claims.getSubject()).thenReturn(OTHER_USER);
        lenient().when(claims.get("role", String.class)).thenReturn("PATIENT");
    }

    private static MockHttpServletRequestBuilder asOtherPatientViaBasic(final String path) {
        final String credentials = Base64.getEncoder()
                .encodeToString((OTHER_USER + ":" + OTHER_USER_PASSWORD).getBytes(StandardCharsets.UTF_8));
        return get(path).header(HttpHeaders.AUTHORIZATION, "Basic " + credentials);
    }

    @Nested
    @DisplayName("Already secure (regression guards)")
    class AlreadySecure {

        @ParameterizedTest(name = "{0}: anonymous GET {1} is 401 and generates nothing")
        @CsvSource({
                "TC-EMG-001, /v1/api/emergency/VIAL1.pdf",
                "TC-EMG-002, /v1/api/emergency/download/VIAL1.pdf",
                "TC-EMG-003, /v1/api/emergency/debug/VIAL1",
                "TC-EMG-004, /v1/api/emergency/health"})
        void anonymousIsRefused(final String id, final String path) throws Exception {
            mvc.perform(get(path)).andExpect(status().isUnauthorized());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-005: a bearer token that does not validate is 401 and generates nothing")
        void invalidTokenIsRefused() throws Exception {
            mvc.perform(get(PATIENT_ONE_PDF).header(HttpHeaders.AUTHORIZATION, "Bearer not-a-real-token"))
                    .andExpect(status().isUnauthorized());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-006: wrong Basic credentials are 401 and generate nothing")
        void wrongBasicCredentialsAreRefused() throws Exception {
            final String credentials = Base64.getEncoder()
                    .encodeToString((OTHER_USER + ":wrong").getBytes(StandardCharsets.UTF_8));
            mvc.perform(get(PATIENT_ONE_PDF).header(HttpHeaders.AUTHORIZATION, "Basic " + credentials))
                    .andExpect(status().isUnauthorized());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }
    }

    @Nested
    @DisplayName("DEF-EMG-01 and DEF-EMG-03 fixed for now (PR #336), until CR-1 Increment 2 replaces these endpoints")
    class InterimFix {

        @Test
        @DisplayName("TC-EMG-011: another signed-in patient is refused patient 1's PDF and nothing is generated")
        void otherPatientIsRefused() throws Exception {
            mvc.perform(asOtherPatientViaBasic(PATIENT_ONE_PDF))
                    .andExpect(status().isNotFound());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-008: DEF-EMG-01 fixed (interim): another patient signed in with Basic auth gets 404 from /download/{id}.pdf and nothing is generated")
        void otherPatientIsRefusedTheDownload() throws Exception {
            mvc.perform(asOtherPatientViaBasic("/v1/api/emergency/download/VIAL1.pdf"))
                    .andExpect(status().isNotFound());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-148: DEF-EMG-01 interim fix: patient 1 signed in with Basic auth still gets their own PDF")
        void thePatientStillGetsTheirOwnPdf() throws Exception {
            when(securityUtil.resolveCurrentUser())
                    .thenReturn(com.careconnect.model.User.builder().id(PATIENT_ONE_USER).role(Role.PATIENT).build());
            mvc.perform(asOtherPatientViaBasic(PATIENT_ONE_PDF))
                    .andExpect(status().isOk())
                    .andExpect(content().contentType("application/pdf"));
            verify(vialOfLifePdfService).generateVialOfLifePdf("VIAL1");
        }

        @Test
        @DisplayName("TC-EMG-012: the debug endpoint is not reachable by a patient account: 404, no internal details, nothing generated")
        void debugEndpointIsClosed() throws Exception {
            lenient().when(vialOfLifePdfService.generateVialOfLifePdf("VIAL1"))
                    .thenThrow(new IllegalStateException("synthetic internal detail"));
            mvc.perform(asOtherPatientViaBasic("/v1/api/emergency/debug/VIAL1"))
                    .andExpect(status().isNotFound())
                    .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("synthetic internal detail"))));
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-197: a refusal, an unknown patient and a malformed ID get the same 404 (status, headers and body), so IDs cannot be probed")
        void refusalLooksLikeAnUnknownId() throws Exception {
            final MvcResult refused = mvc.perform(asOtherPatientViaBasic(PATIENT_ONE_PDF)).andReturn();
            final MvcResult unknown = mvc.perform(asOtherPatientViaBasic("/v1/api/emergency/VIAL999.pdf")).andReturn();
            final MvcResult malformed = mvc.perform(asOtherPatientViaBasic("/v1/api/emergency/VIALabc.pdf")).andReturn();

            assertThat(refused.getResponse().getStatus()).isEqualTo(404);
            for (final MvcResult other : List.of(unknown, malformed)) {
                assertThat(other.getResponse().getStatus()).isEqualTo(404);
                assertThat(other.getResponse().getContentAsByteArray()).isEqualTo(refused.getResponse().getContentAsByteArray());
                assertThat(headers(other)).isEqualTo(headers(refused));
            }
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        private Map<String, List<String>> headers(final MvcResult result) {
            final Map<String, List<String>> map = new TreeMap<>();
            for (final String name : result.getResponse().getHeaderNames()) {
                map.put(name, result.getResponse().getHeaders(name));
            }
            return map;
        }
    }

    @Nested
    @DisplayName("Current gaps (characterization of DEF-EMG-02; each fails once its gap is fixed)")
    class CurrentGaps {

        @Test
        @DisplayName("TC-EMG-009: GAP 2 (DEF-EMG-02): a valid sign-in token is ignored on emergency paths, so even the patient gets 401")
        void validTokenIsIgnored() throws Exception {
            mvc.perform(get(PATIENT_ONE_PDF).header(HttpHeaders.AUTHORIZATION, "Bearer " + VALID_TOKEN))
                    .andExpect(status().isUnauthorized());
            verify(jwtTokenProvider, never()).validateToken(anyString());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-013: GAP 2 (DEF-EMG-02): a valid sign-in cookie (AUTH) is ignored on emergency paths too")
        void validCookieIsIgnored() throws Exception {
            mvc.perform(get(PATIENT_ONE_PDF).cookie(new Cookie("AUTH", VALID_TOKEN)))
                    .andExpect(status().isUnauthorized());
            verify(jwtTokenProvider, never()).validateToken(anyString());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }
    }

    @Nested
    @DisplayName("Target behaviour (enable when DEF-EMG-02 is fixed)")
    class Target {

        @Test
        @Disabled("CR-1 Increment 2: once the sign-in token is read on these paths (GAP 2), "
                + "another patient's token must still be refused (GAP 1)")
        @DisplayName("TC-EMG-014: another patient's valid sign-in token is refused patient 1's PDF and nothing is generated")
        void otherPatientsTokenIsRefused() throws Exception {
            mvc.perform(get(PATIENT_ONE_PDF).header(HttpHeaders.AUTHORIZATION, "Bearer " + VALID_TOKEN))
                    .andExpect(status().isNotFound());
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }
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
