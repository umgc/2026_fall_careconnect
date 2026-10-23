package com.careconnect.controller.emergency;

import com.careconnect.dto.emergency.PassportDtos.NewTokenResponse;
import com.careconnect.dto.emergency.PassportDtos.ProfileRequest;
import com.careconnect.dto.emergency.PassportDtos.PublicPassport;
import com.careconnect.exception.AppException;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.emergency.BloodType;
import com.careconnect.model.emergency.PassportField;
import com.careconnect.dto.emergency.PassportDtos.VisibilityRequest;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.emergency.EmergencyPassportService;
import com.careconnect.service.emergency.PassportScanRateLimiter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The passport controller's own decisions: who counts as the patient, how a scan answers each case,
 * and which address the rate limit keys on. The service is mocked; its rules have their own test.
 * <p>
 * Test Plan §3.24.3: TC-EMG-093…099 (author) and TC-EMG-116…120, 125, 129 (Testing Lead). Test IDs are permanent.
 */
class EmergencyPassportControllerTest {

    private static final String EMAIL = "patient@example.test";
    private static final Authentication SIGNED_IN = new UsernamePasswordAuthenticationToken(EMAIL, null, List.of());

    private EmergencyPassportService passports;
    private PassportScanRateLimiter rateLimiter;
    private UserRepository users;
    private PatientRepository patients;
    private EmergencyPassportController controller;

    @BeforeEach
    void setUp() {
        passports = mock(EmergencyPassportService.class);
        rateLimiter = mock(PassportScanRateLimiter.class);
        users = mock(UserRepository.class);
        patients = mock(PatientRepository.class);
        controller = new EmergencyPassportController(passports, rateLimiter, users, patients);
        when(rateLimiter.tryAcquire(anyString())).thenReturn(true);
    }

    @Test
    @DisplayName("TC-EMG-093: a valid scan is 200 and never cached")
    void validScanIsOkAndNoStore() {
        PublicPassport passport = new PublicPassport("Jordan Miller", 41, null, null, null, null, null, null);
        when(passports.scan("good")).thenReturn(Optional.of(passport));

        ResponseEntity<?> response = controller.scan("good", new MockHttpServletRequest());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(passport);
        assertThat(response.getHeaders().getCacheControl()).isEqualTo("no-store");
    }

    @Test
    @DisplayName("TC-EMG-094: an unknown or revoked code is the same 404")
    void inactiveScanIsUniform404() {
        when(passports.scan(anyString())).thenReturn(Optional.empty());

        ResponseEntity<?> response = controller.scan("anything", new MockHttpServletRequest());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).isEqualTo(Map.of("status", "NOT_ACTIVE"));
    }

    @Test
    @DisplayName("TC-EMG-095: over the limit is 429 and the code is never looked up")
    void rateLimitedScanIs429() {
        when(rateLimiter.tryAcquire(anyString())).thenReturn(false);

        ResponseEntity<?> response = controller.scan("anything", new MockHttpServletRequest());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        verify(passports, never()).scan(anyString());
    }

    @Test
    @DisplayName("TC-EMG-096: the rate limit keys on the address the load balancer appended, not one the client sent")
    void clientKeyIsTheLastForwardedHop() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr("10.0.0.9");
        request.addHeader("X-Forwarded-For", "1.2.3.4, 203.0.113.5");
        assertThat(EmergencyPassportController.clientKey(request)).isEqualTo("203.0.113.5");

        MockHttpServletRequest direct = new MockHttpServletRequest();
        direct.setRemoteAddr("10.0.0.9");
        assertThat(EmergencyPassportController.clientKey(direct)).isEqualTo("10.0.0.9");
    }

    @Test
    @DisplayName("TC-EMG-097: a signed-in user with no patient record cannot manage a passport")
    void nonPatientIsForbidden() {
        User caregiver = User.builder().id(9L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(caregiver));
        when(patients.findByUserId(9L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> controller.get(SIGNED_IN))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("TC-EMG-098: an unknown blood type or malformed JSON is 400 naming the problem, not the global handler's 500")
    void unreadableBodyIs400() throws Exception {
        // Real Spring MVC and Jackson, with the global handler present, so this proves which one wins.
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc.perform(put("/v1/api/passport/profile").principal(SIGNED_IN)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"bloodType\":\"Z_POS\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("bloodType must be one of: A_POSITIVE, A_NEGATIVE, "
                        + "B_POSITIVE, B_NEGATIVE, AB_POSITIVE, AB_NEGATIVE, O_POSITIVE, O_NEGATIVE"));

        mvc.perform(put("/v1/api/passport/visibility/allergies").principal(SIGNED_IN)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"isPublic\":"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Request body is malformed"));
        verify(passports, never()).updateProfile(any(), any());
    }

    @Test
    @DisplayName("TC-EMG-099: an unknown field name is 404 and a missing isPublic is 400")
    void visibilityRequestValidation() {
        User user = User.builder().id(9L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(patients.findByUserId(9L)).thenReturn(Optional.of(Patient.builder().id(42L).build()));

        assertThatThrownBy(() -> controller.setVisibility("SSN", new VisibilityRequest(true), SIGNED_IN))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.NOT_FOUND);
        assertThatThrownBy(() -> controller.setVisibility("allergies", new VisibilityRequest(null), SIGNED_IN))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // ---- Testing Lead cases (TC-EMG-116…120, 125) ----

    @Test
    @DisplayName("TC-EMG-116: every owner endpoint acts on the signed-in patient's own record; a new code is 201 and "
            + "never cached, a revoke is 204")
    void ownerEndpointsUseTheSignedInPatient() {
        signedInAsPatient(42L);
        NewTokenResponse made = new NewTokenResponse("raw", "https://app.example.test/passport/raw", null);
        when(passports.regenerateToken(42L)).thenReturn(made);
        ProfileRequest profile = new ProfileRequest(BloodType.A_NEGATIVE, null, null, null, null);

        assertThat(controller.get(SIGNED_IN).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(controller.updateProfile(profile, SIGNED_IN).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(controller.setVisibility(" Allergies ", new VisibilityRequest(true), SIGNED_IN).getStatusCode())
                .isEqualTo(HttpStatus.OK);
        ResponseEntity<NewTokenResponse> created = controller.regenerateToken(SIGNED_IN);
        ResponseEntity<Void> revoked = controller.revokeToken(SIGNED_IN);

        verify(passports).getPassport(42L);
        verify(passports).updateProfile(42L, profile);
        verify(passports).setVisibility(42L, PassportField.ALLERGIES, true);
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(created.getHeaders().getCacheControl()).isEqualTo("no-store");
        assertThat(created.getBody()).isEqualTo(made);
        verify(passports).revokeToken(42L);
        assertThat(revoked.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
    }

    @Test
    @DisplayName("TC-EMG-117: no sign-in is 401, and a sign-in whose account no longer exists is 403")
    void missingOrUnknownAccountIsRefused() {
        assertThatThrownBy(() -> controller.get(null))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.UNAUTHORIZED);

        when(users.findByEmail(EMAIL)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> controller.revokeToken(SIGNED_IN))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.FORBIDDEN);
        verify(passports, never()).revokeToken(any());
    }

    @Test
    @DisplayName("TC-EMG-118: the 404 and 429 scan answers are never cached either, and the 429 says RATE_LIMITED")
    void refusedScansAreNotCached() {
        when(passports.scan(anyString())).thenReturn(Optional.empty());
        ResponseEntity<?> notActive = controller.scan("anything", new MockHttpServletRequest());

        when(rateLimiter.tryAcquire(anyString())).thenReturn(false);
        ResponseEntity<?> limited = controller.scan("anything", new MockHttpServletRequest());

        assertThat(notActive.getHeaders().getCacheControl()).isEqualTo("no-store");
        assertThat(limited.getHeaders().getCacheControl()).isEqualTo("no-store");
        assertThat(limited.getBody()).isEqualTo(Map.of("status", "RATE_LIMITED"));
    }

    @Test
    @DisplayName("TC-EMG-119: a blank X-Forwarded-For or an empty last hop falls back to the connecting address; "
            + "a single hop is used as it is")
    void clientKeyFallsBackWhenTheLastHopIsMissing() {
        MockHttpServletRequest blank = new MockHttpServletRequest();
        blank.setRemoteAddr("10.0.0.9");
        blank.addHeader("X-Forwarded-For", "   ");
        assertThat(EmergencyPassportController.clientKey(blank)).isEqualTo("10.0.0.9");

        MockHttpServletRequest emptyLast = new MockHttpServletRequest();
        emptyLast.setRemoteAddr("10.0.0.9");
        emptyLast.addHeader("X-Forwarded-For", "1.2.3.4,  ");
        assertThat(EmergencyPassportController.clientKey(emptyLast)).isEqualTo("10.0.0.9");

        MockHttpServletRequest single = new MockHttpServletRequest();
        single.setRemoteAddr("10.0.0.9");
        single.addHeader("X-Forwarded-For", " 203.0.113.9 ");
        assertThat(EmergencyPassportController.clientKey(single)).isEqualTo("203.0.113.9");
    }

    @Test
    @DisplayName("TC-EMG-120: a value of the wrong type that is not an enum, such as isPublic \"maybe\", is the "
            + "generic 400, not a 500")
    void wrongTypedValueIsGenericBadRequest() throws Exception {
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc.perform(put("/v1/api/passport/visibility/allergies").principal(SIGNED_IN)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"isPublic\":\"maybe\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Request body is malformed"));
        verify(passports, never()).setVisibility(any(), any(), org.mockito.ArgumentMatchers.anyBoolean());
    }

    @Test
    @DisplayName("TC-EMG-125: a save that collides with a simultaneous one on a unique index is 409, not the global "
            + "handler's 500 (DEF-EMG-05)")
    void concurrentSaveIsConflict() throws Exception {
        signedInAsPatient(42L);
        when(passports.regenerateToken(42L)).thenThrow(new DataIntegrityViolationException(
                "duplicate key value violates unique constraint \"uq_emergency_passport_token_one_active\""));
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc.perform(post("/v1/api/passport/token").principal(SIGNED_IN))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error")
                        .value("Another change to this passport was saved at the same moment; try again"));
    }

    @Test
    @DisplayName("TC-EMG-129: the scan path with no code is the same rate-limited, uncached 404 NOT_ACTIVE, not the "
            + "global handler's 500 (DEF-EMG-06)")
    void emptyCodeIsTheUniform404() throws Exception {
        when(passports.scan(null)).thenReturn(Optional.empty());
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/v1/api/passport/scan/"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value("NOT_ACTIVE"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("Cache-Control", "no-store"));
        verify(rateLimiter).tryAcquire(anyString());
    }

    private void signedInAsPatient(long patientId) {
        User user = User.builder().id(9L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(patients.findByUserId(9L)).thenReturn(Optional.of(Patient.builder().id(patientId).build()));
    }
}
