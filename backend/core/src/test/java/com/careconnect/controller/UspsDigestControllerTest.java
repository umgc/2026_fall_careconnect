package com.careconnect.controller;

import com.careconnect.dto.NaturalLanguageMailSearchResponse;
import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.NaturalLanguageMailSearchService;
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
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
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
    private UserRepository userRepository;

    @Mock
    private Jwt jwt;

    @InjectMocks
    private UspsDigestController controller;

    @BeforeEach
    void setUp() {
        User mockPatient = mock(User.class);
        lenient().when(mockPatient.getId()).thenReturn(1L);
        lenient().when(userRepository.findByEmail(any())).thenReturn(Optional.of(mockPatient));
    }

    private USPSDigest digest() {
        return new USPSDigest(null, List.of(), List.of());
    }

    // ─── getLatestDigest ──────────────────────────────────────────────────────

    @Test
    void getLatestDigest_dateProvided_callsDigestForDate_returnsOk() throws Exception {
        final LocalDate date = LocalDate.of(2025, 6, 1);
        final USPSDigest d = digest();
        when(uspsDigestService.digestForDate("user1@example.com", date)).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, "user1@example.com", date);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(d);
        verify(uspsDigestService).digestForDate("user1@example.com", date);
    }

    @Test
    void getLatestDigest_dateNull_callsLatestForUser_returnsOk() throws Exception {
        final USPSDigest d = digest();
        when(uspsDigestService.latestForUser("patient@example.com")).thenReturn(Optional.of(d));

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, "patient@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(d);
        verify(uspsDigestService).latestForUser("patient@example.com");
    }

    @Test
    void getLatestDigest_notFound_returnsNoContent() throws Exception {
        when(uspsDigestService.latestForUser("patient@example.com")).thenReturn(Optional.empty());

        final ResponseEntity<USPSDigest> response = controller.getLatestDigest(jwt, "patient@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
    }

    // ─── search ───────────────────────────────────────────────────────────────

    @Test
    void search_returnsOkWithResults() throws Exception {
        final List<Map<String, Object>> results = List.of(Map.of("key", "value"));
        when(uspsDigestService.search("user1@example.com", "invoice")).thenReturn(results);

        final ResponseEntity<List<Map<String, Object>>> response = controller.search(jwt, "user1@example.com", "invoice");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(results);
        verify(uspsDigestService).search("user1@example.com", "invoice");
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

    // ─── clearCache ───────────────────────────────────────────────────────────

    @Test
    void clearCache_returnsOkWithMessage() throws Exception {
        doNothing().when(uspsDigestService).clearCacheForUser("user1@example.com");

        final ResponseEntity<String> response = controller.clearCache(jwt, "user1@example.com");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("user1@example.com");
        verify(uspsDigestService).clearCacheForUser("user1@example.com");
    }
}
