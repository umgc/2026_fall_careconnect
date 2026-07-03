package com.careconnect.controller;

import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.USPSDigestService;
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
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class UspsDigestControllerTest {

    @Mock
    private USPSDigestService uspsDigestService;

    @Mock
    private SecurityUtil securityUtil;

    @Mock
    private AuthorizationService authorizationService;

    @Mock
    private UserRepository userRepository;

    @Mock
    private Jwt jwt;

    @InjectMocks
    private UspsDigestController controller;

    private User mockCaller;
    private User mockPatient;

    @BeforeEach
    void setUp() {
        mockCaller = mock(User.class);
        mockPatient = mock(User.class);
        when(mockPatient.getId()).thenReturn(1L);
        when(securityUtil.resolveCurrentUser()).thenReturn(mockCaller);
        lenient().when(userRepository.findByEmail(any())).thenReturn(Optional.of(mockPatient));
        lenient().when(userRepository.findById(1L)).thenReturn(Optional.of(mockPatient));
    }

    private USPSDigest digest() {
        return new USPSDigest(null, List.of(), List.of());
    }

    // ─── getLatestDigest ──────────────────────────────────────────────────────

    @Test
    void getLatestDigest_dateProvided_callsDigestForDate_returnsOk() throws Exception {
        final LocalDate date = LocalDate.of(2025, 6, 1);
        final USPSDigest d = digest();
        when(uspsDigestService.digestForDate("1", date)).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, "user1@example.com", date);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(d);
        verify(uspsDigestService).digestForDate("1", date);
        verify(authorizationService).requirePatientAccess(mockCaller, 1L);
    }

    @Test
    void getLatestDigest_dateNull_callsLatestForUser_returnsOk() throws Exception {
        final USPSDigest d = digest();
        when(uspsDigestService.latestForUser("1")).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, "patient@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(d);
        verify(uspsDigestService).latestForUser("1");
        verify(authorizationService).requirePatientAccess(mockCaller, 1L);
    }

    @Test
    void getLatestDigest_numericPatientId_resolvesByDatabaseId() throws Exception {
        final USPSDigest d = digest();
        when(userRepository.findByEmail("1")).thenReturn(Optional.empty());
        when(uspsDigestService.latestForUser("1")).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, "1", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(userRepository).findById(1L);
        verify(uspsDigestService).latestForUser("1");
    }

    @Test
    void getLatestDigest_notFound_returnsNoContent() throws Exception {
        when(uspsDigestService.latestForUser("1")).thenReturn(Optional.empty());

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, "patient@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
    }

    // ─── search ───────────────────────────────────────────────────────────────

    @Test
    void search_returnsOkWithResults() throws Exception {
        final List<Map<String, Object>> results = List.of(Map.of("key", "value"));
        when(uspsDigestService.search("1", "invoice")).thenReturn(results);

        final ResponseEntity<List<Map<String, Object>>> response = controller.search(jwt, "user1@example.com", "invoice");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(results);
        verify(uspsDigestService).search("1", "invoice");
        verify(authorizationService).requirePatientAccess(mockCaller, 1L);
    }

    // ─── clearCache ───────────────────────────────────────────────────────────

    @Test
    void clearCache_returnsOkWithMessage() throws Exception {
        doNothing().when(uspsDigestService).clearCacheForUser("1");

        final ResponseEntity<String> response = controller.clearCache(jwt, "user1@example.com");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("user1@example.com");
        verify(uspsDigestService).clearCacheForUser("1");
        verify(authorizationService).requirePatientAccess(mockCaller, 1L);
    }
}
