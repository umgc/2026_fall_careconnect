package com.careconnect.controller;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.NaturalLanguageMailSearchService;
import com.careconnect.service.USPSDigestService;
import com.careconnect.service.UspsPatientResolver;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.MethodParameter;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import java.util.List;
import java.util.Optional;

import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end HTTP tests for USPS patient-scoped authorization (PR #160).
 * Exercises controller HTTP mapping, JWT presence checks, patient resolution, and access control.
 */
@ExtendWith(MockitoExtension.class)
class UspsPatientAccessE2ETest {

    private static final String JWT_REQUEST_ATTR = "test.jwt";

    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @Mock
    private USPSDigestService uspsDigestService;
    @Mock
    private UspsPatientResolver patientResolver;
    @Mock
    private NaturalLanguageMailSearchService naturalLanguageMailSearchService;

    private MockMvc mailMvc;
    private MockMvc digestMvc;
    private User caregiver;
    private User patient;
    private Jwt jwt;

    @BeforeEach
    void setUp() throws Exception {
        HandlerMethodArgumentResolver jwtResolver = new HandlerMethodArgumentResolver() {
            @Override
            public boolean supportsParameter(MethodParameter parameter) {
                return Jwt.class.isAssignableFrom(parameter.getParameterType())
                        && parameter.hasParameterAnnotation(AuthenticationPrincipal.class);
            }

            @Override
            public Object resolveArgument(MethodParameter parameter, ModelAndViewContainer mavContainer,
                                          NativeWebRequest webRequest, WebDataBinderFactory binderFactory) {
                return webRequest.getAttribute(JWT_REQUEST_ATTR, NativeWebRequest.SCOPE_REQUEST);
            }
        };

        mailMvc = MockMvcBuilders
                .standaloneSetup(new USPSController(securityUtil, authorizationService, uspsDigestService, patientResolver))
                .setCustomArgumentResolvers(jwtResolver)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
        digestMvc = MockMvcBuilders
                .standaloneSetup(new UspsDigestController(securityUtil, authorizationService, uspsDigestService, patientResolver, naturalLanguageMailSearchService))
                .setCustomArgumentResolvers(jwtResolver)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        caregiver = mock(User.class);
        patient = mock(User.class);
        jwt = mock(Jwt.class);
        lenient().when(caregiver.getId()).thenReturn(10L);
        lenient().when(patient.getId()).thenReturn(7L);
        lenient().when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        lenient().when(patientResolver.resolvePatient("patient@example.com", caregiver)).thenReturn(patient);
        lenient().when(patientResolver.resolvePatient("patient@example.com", null, caregiver)).thenReturn(patient);
    }

    private USPSDigest sampleDigest() {
        return new USPSDigest(null, List.of(), List.of());
    }

    @Nested
    @DisplayName("USPSController /v1/api/usps/mail")
    class MailEndpoint {

        @Test
        @DisplayName("linked caregiver can fetch patient digest")
        void linkedCaregiver_returnsOk() throws Exception {
            when(uspsDigestService.latestForUser("7")).thenReturn(Optional.of(sampleDigest()));

            mailMvc.perform(get("/v1/api/usps/mail")
                            .requestAttr(JWT_REQUEST_ATTR, jwt)
                            .param("patientEmail", "patient@example.com"))
                    .andExpect(status().isOk());

            verify(authorizationService).requirePatientAccess(caregiver, 7L);
            verify(uspsDigestService).latestForUser("7");
        }

        @Test
        @DisplayName("unlinked caregiver is denied with 403")
        void unlinkedCaregiver_returnsForbidden() throws Exception {
            doThrow(new UnauthorizedException("Caregiver 'cg@example.com' is not assigned to patient 7"))
                    .when(authorizationService).requirePatientAccess(caregiver, 7L);

            mailMvc.perform(get("/v1/api/usps/mail")
                            .requestAttr(JWT_REQUEST_ATTR, jwt)
                            .param("patientEmail", "patient@example.com"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.error").value("Caregiver 'cg@example.com' is not assigned to patient 7"));
        }

        @Test
        @DisplayName("missing JWT is rejected before patient lookup")
        void missingJwt_returnsForbidden() throws Exception {
            mailMvc.perform(get("/v1/api/usps/mail")
                            .param("patientEmail", "patient@example.com"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.error").value("Missing or invalid authentication token"));
        }
    }

    @Nested
    @DisplayName("UspsDigestController /v1/api/usps/latest")
    class LatestEndpoint {

        @Test
        @DisplayName("linked caregiver can fetch latest digest for assigned patient")
        void linkedCaregiver_returnsOk() throws Exception {
            when(uspsDigestService.latestForUser("7")).thenReturn(Optional.of(sampleDigest()));

            digestMvc.perform(get("/v1/api/usps/latest")
                            .requestAttr(JWT_REQUEST_ATTR, jwt)
                            .param("patientEmail", "patient@example.com"))
                    .andExpect(status().isOk());

            verify(authorizationService).requirePatientAccess(caregiver, 7L);
        }

        @Test
        @DisplayName("unlinked caregiver is denied with 403")
        void unlinkedCaregiver_returnsForbidden() throws Exception {
            doThrow(new UnauthorizedException("Caregiver 'cg@example.com' is not assigned to patient 7"))
                    .when(authorizationService).requirePatientAccess(caregiver, 7L);

            digestMvc.perform(get("/v1/api/usps/latest")
                            .requestAttr(JWT_REQUEST_ATTR, jwt)
                            .param("patientEmail", "patient@example.com"))
                    .andExpect(status().isForbidden());
        }
    }

    @Nested
    @DisplayName("UspsDigestController /v1/api/usps/clear-cache")
    class ClearCacheEndpoint {

        @Test
        @DisplayName("linked caregiver can clear cache for assigned patient")
        void linkedCaregiver_returnsOk() throws Exception {
            digestMvc.perform(post("/v1/api/usps/clear-cache")
                            .requestAttr(JWT_REQUEST_ATTR, jwt)
                            .param("patientEmail", "patient@example.com")
                            .contentType(MediaType.APPLICATION_FORM_URLENCODED))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$").value("Cache cleared successfully for user: patient@example.com"));

            verify(uspsDigestService).clearCacheForUser("7");
            verify(authorizationService).requirePatientAccess(caregiver, 7L);
        }

        @Test
        @DisplayName("unlinked caregiver cannot clear cache")
        void unlinkedCaregiver_returnsForbidden() throws Exception {
            doThrow(new UnauthorizedException("Caregiver 'cg@example.com' is not assigned to patient 7"))
                    .when(authorizationService).requirePatientAccess(caregiver, 7L);

            digestMvc.perform(post("/v1/api/usps/clear-cache")
                            .requestAttr(JWT_REQUEST_ATTR, jwt)
                            .param("patientEmail", "patient@example.com"))
                    .andExpect(status().isForbidden());
        }
    }
}
