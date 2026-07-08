package com.careconnect.controller;

import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.USPSDigestService;
import com.careconnect.service.UspsPatientResolver;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class USPSControllerTest {

    @Mock
    private USPSDigestService service;

    @Mock
    private SecurityUtil securityUtil;

    @Mock
    private AuthorizationService authorizationService;

    @Mock
    private UspsPatientResolver patientResolver;

    @InjectMocks
    private USPSController controller;

    private User mockCaller;

    @BeforeEach
    void setUp() throws Exception {
        mockCaller = mock(User.class);
        lenient().when(mockCaller.getId()).thenReturn(42L);
        lenient().when(securityUtil.resolveCurrentUser()).thenReturn(mockCaller);
        lenient().when(patientResolver.resolvePatient(isNull(), eq(mockCaller))).thenReturn(mockCaller);
    }

    private USPSDigest emptyDigest() {
        return new USPSDigest(null, List.of(), List.of());
    }

    // ─── getDigest ────────────────────────────────────────────────────────────

    @Test
    void getDigest_jwtPresentDatePresent_callsDigestForDateForCurrentUser() throws Exception {
        final Jwt jwt = mock(Jwt.class);
        final LocalDate date = LocalDate.of(2025, 1, 15);
        final USPSDigest digest = emptyDigest();
        when(service.digestForDate("42", date)).thenReturn(Optional.of(digest));

        final ResponseEntity<USPSDigest> response = controller.getDigest(jwt, null, date);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(digest);
        verify(service).digestForDate("42", date);
        verify(authorizationService).requirePatientAccess(mockCaller, 42L);
    }

    @Test
    void getDigest_jwtPresentDateNull_callsLatestForUserForCurrentUser() throws Exception {
        final Jwt jwt = mock(Jwt.class);
        final USPSDigest digest = emptyDigest();
        when(service.latestForUser("42")).thenReturn(Optional.of(digest));

        final ResponseEntity<USPSDigest> response = controller.getDigest(jwt, null, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(digest);
        verify(service).latestForUser("42");
        verify(authorizationService).requirePatientAccess(mockCaller, 42L);
    }

    @Test
    void getDigest_patientEmailProvided_resolvesPatientAndUsesDatabaseId() throws Exception {
        final Jwt jwt = mock(Jwt.class);
        final User patient = mock(User.class);
        when(patient.getId()).thenReturn(7L);
        when(patientResolver.resolvePatient("patient@example.com", mockCaller)).thenReturn(patient);
        when(service.latestForUser("7")).thenReturn(Optional.empty());

        final ResponseEntity<USPSDigest> response = controller.getDigest(jwt, "patient@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        verify(authorizationService).requirePatientAccess(mockCaller, 7L);
        verify(service).latestForUser("7");
    }

    @Test
    void getDigest_jwtNull_throwsUnauthorized() {
        assertThatThrownBy(() -> controller.getDigest(null, null, null))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Missing or invalid authentication token");
    }

    @Test
    void getDigest_unlinkedCaregiver_throwsUnauthorized() throws Exception {
        final Jwt jwt = mock(Jwt.class);
        final User patient = mock(User.class);
        when(patient.getId()).thenReturn(7L);
        when(patientResolver.resolvePatient("patient@example.com", mockCaller)).thenReturn(patient);
        doThrow(new UnauthorizedException("Caregiver is not assigned to patient 7"))
                .when(authorizationService).requirePatientAccess(mockCaller, 7L);

        assertThatThrownBy(() -> controller.getDigest(jwt, "patient@example.com", null))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("not assigned");
    }
}
