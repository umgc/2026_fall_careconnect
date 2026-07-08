package com.careconnect.controller;

import com.careconnect.dto.NaturalLanguageMailSearchResponse;
import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.NaturalLanguageMailSearchService;
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
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class UspsDigestControllerTest {

    @Mock
    private USPSDigestService uspsDigestService;

    @Mock
    private NaturalLanguageMailSearchService naturalLanguageMailSearchService;

    @Mock
    private SecurityUtil securityUtil;

    @Mock
    private AuthorizationService authorizationService;

    @Mock
    private UspsPatientResolver patientResolver;

    @Mock
    private Jwt jwt;

    @InjectMocks
    private UspsDigestController controller;

    private User mockCaller;
    private User mockPatient;

    @BeforeEach
    void setUp() throws Exception {
        mockCaller = mock(User.class);
        mockPatient = mock(User.class);
        lenient().when(mockCaller.getId()).thenReturn(99L);
        lenient().when(mockPatient.getId()).thenReturn(1L);
        when(securityUtil.resolveCurrentUser()).thenReturn(mockCaller);
        lenient().when(patientResolver.resolvePatient(any(), any(), eq(mockCaller))).thenReturn(mockPatient);
        lenient().when(patientResolver.resolvePatient(isNull(), isNull(), eq(mockCaller))).thenReturn(mockCaller);
    }

    private USPSDigest digest() {
        return new USPSDigest(null, List.of(), List.of());
    }

    @Test
    void getLatestDigest_dateProvided_callsDigestForDate_returnsOk() throws Exception {
        final LocalDate date = LocalDate.of(2025, 6, 1);
        final USPSDigest d = digest();
        when(uspsDigestService.digestForDate("1", date)).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response =
                controller.getLatestDigest(jwt, "user1@example.com", null, date);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(d);
        verify(uspsDigestService).digestForDate("1", date);
        verify(authorizationService).requirePatientAccess(mockCaller, 1L);
    }

    @Test
    void getLatestDigest_dateNull_callsLatestForUser_returnsOk() throws Exception {
        final USPSDigest d = digest();
        when(uspsDigestService.latestForUser("1")).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response =
                controller.getLatestDigest(jwt, "patient@example.com", null, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(uspsDigestService).latestForUser("1");
    }

    @Test
    void getLatestDigest_legacyUserIdParam_resolvesByDatabaseId() throws Exception {
        final USPSDigest d = digest();
        when(patientResolver.resolvePatient(null, "1", mockCaller)).thenReturn(mockPatient);
        when(uspsDigestService.latestForUser("1")).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, null, "1", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(uspsDigestService).latestForUser("1");
    }

    @Test
    void getLatestDigest_noPatientParam_defaultsToCurrentUser() throws Exception {
        final USPSDigest d = digest();
        when(patientResolver.resolvePatient(null, null, mockCaller)).thenReturn(mockCaller);
        when(uspsDigestService.latestForUser("99")).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, null, null, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(authorizationService).requirePatientAccess(mockCaller, 99L);
        verify(uspsDigestService).latestForUser("99");
    }

    @Test
    void getLatestDigest_notFound_returnsNoContent() throws Exception {
        when(uspsDigestService.latestForUser("1")).thenReturn(Optional.empty());

        final ResponseEntity<USPSDigest> response =
                controller.getLatestDigest(jwt, "patient@example.com", null, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
    }

    @Test
    void search_returnsOkWithResults() throws Exception {
        final List<Map<String, Object>> results = List.of(Map.of("key", "value"));
        when(uspsDigestService.search("1", "invoice")).thenReturn(results);

        final ResponseEntity<List<Map<String, Object>>> response =
                controller.search(jwt, "user1@example.com", null, "invoice");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(results);
        verify(uspsDigestService).search("1", "invoice");
    }

    @Test
    void naturalLanguageSearch_returnsOk() throws Exception {
        final User user = new User();
        when(securityUtil.resolveCurrentUser()).thenReturn(user);
        final NaturalLanguageMailSearchResponse body =
                new NaturalLanguageMailSearchResponse(42L, "pharmacy bills", List.of("pharmacy", "bills"),
                        0, List.of());
        when(naturalLanguageMailSearchService.search(eq(user), eq(42L), eq("pharmacy bills"), eq(20)))
                .thenReturn(body);

        final ResponseEntity<NaturalLanguageMailSearchResponse> response =
                controller.naturalLanguageSearch(42L, "pharmacy bills", 20);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(body);
        verify(naturalLanguageMailSearchService).search(user, 42L, "pharmacy bills", 20);
    }

    // â”€â”€â”€ clearCache â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @Test
    void clearCache_returnsOkWithMessage() throws Exception {
        doNothing().when(uspsDigestService).clearCacheForUser("1");

        final ResponseEntity<String> response = controller.clearCache(jwt, "user1@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("user1@example.com");
        verify(uspsDigestService).clearCacheForUser("1");
    }

    @Test
    void getLatestDigest_unlinkedCaregiver_throwsUnauthorized() throws Exception {
        doThrow(new UnauthorizedException("Caregiver is not assigned to patient 1"))
                .when(authorizationService).requirePatientAccess(mockCaller, 1L);

        org.assertj.core.api.Assertions.assertThatThrownBy(
                        () -> controller.getLatestDigest(jwt, "patient@example.com", null, null))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("not assigned");
    }
}
