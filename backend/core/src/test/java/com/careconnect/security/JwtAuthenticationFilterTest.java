package com.careconnect.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;

import java.util.Arrays;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class JwtAuthenticationFilterTest {

    @Mock
    private JwtTokenProvider jwtTokenProvider;

    @Mock
    private UserDetailsService userDetailsService;

    @Mock
    private HttpServletRequest request;

    @Mock
    private HttpServletResponse response;

    @Mock
    private FilterChain filterChain;

    @Mock
    private UserDetails userDetails;

    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        jwtAuthenticationFilter = new JwtAuthenticationFilter(jwtTokenProvider, userDetailsService);
    }

    /**
     * The filter puts its sign-in on this thread. Clear it, or a later test on the thread (such as
     * EmergencyAccessRealAuthorizationTest) starts its request signed in as a user with no name.
     */
    @AfterEach
    void clearSignIn() {
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("TC-SEC-006: shouldNotFilter returns true for every path still on the exclusion list")
    void shouldNotFilter_ShouldReturnTrueForExcludedPaths() throws Exception {
        // The whole list as PR #343 leaves it, asserted with JUnit (a bare assert needs -ea).
        for (final String path : Arrays.asList("/swagger-ui", "/v3/api-docs", "/swagger-resources", "/webjars",
                "/v1/api/auth", "/api/v1/auth", "/v1/api/test", "/v1/api/email-test")) {
            when(request.getRequestURI()).thenReturn(path);
            org.junit.jupiter.api.Assertions.assertTrue(jwtAuthenticationFilter.shouldNotFilter(request), path);
        }
    }

    @Test
    @DisplayName("TC-SEC-007: shouldNotFilter should return false for non-excluded paths")
    void shouldNotFilter_ShouldReturnFalseForNonExcludedPaths() throws Exception {
        when(request.getRequestURI()).thenReturn("/api/some-protected-endpoint");
        assert !jwtAuthenticationFilter.shouldNotFilter(request);
    }

    @Test
    @DisplayName("TC-SEC-008: DEF-EMG-02: the emergency PDF paths are filtered, so a signed-in user's token is read there")
    void shouldNotFilter_ShouldReturnFalseForEmergencyPaths() throws Exception {
        for (final String path : Arrays.asList("/v1/api/emergency/VIAL1.pdf",
                "/v1/api/emergency/download/VIAL1.pdf", "/v1/api/emergency/debug/VIAL1")) {
            when(request.getRequestURI()).thenReturn(path);
            org.junit.jupiter.api.Assertions.assertFalse(jwtAuthenticationFilter.shouldNotFilter(request), path);
        }
    }

    @Test
    @DisplayName("TC-SEC-009: resolveToken should return token from Authorization header")
    void resolveToken_ShouldReturnTokenFromHeader() throws Exception {
        when(request.getHeader("Authorization")).thenReturn("Bearer test-token");
        String token = jwtAuthenticationFilter.resolveToken(request);
        assert token.equals("test-token");
    }

    @Test
    @DisplayName("TC-SEC-010: resolveToken should return token from cookie")
    void resolveToken_ShouldReturnTokenFromCookie() throws Exception {
        Cookie cookie = new Cookie("AUTH", "cookie-token");
        when(request.getCookies()).thenReturn(new Cookie[]{cookie});
        when(request.getHeader("Authorization")).thenReturn(null);
        String token = jwtAuthenticationFilter.resolveToken(request);
        assert token.equals("cookie-token");
    }

    @Test
    @DisplayName("TC-SEC-011: resolveToken should return null when no token present")
    void resolveToken_ShouldReturnNullWhenNoToken() throws Exception {
        when(request.getHeader("Authorization")).thenReturn(null);
        when(request.getCookies()).thenReturn(null);
        String token = jwtAuthenticationFilter.resolveToken(request);
        assert token == null;
    }

    @Test
    @DisplayName("TC-SEC-012: doFilterInternal should process valid token and set authentication")
    void doFilterInternal_ShouldProcessValidToken() throws Exception {
        // Arrange
        String token = "valid-token";
        String email = "test@example.com";
        String role = "PATIENT";

        when(request.getRequestURI()).thenReturn("/api/protected");
        when(jwtTokenProvider.validateToken(token)).thenReturn(true);
        when(jwtTokenProvider.getClaims(token)).thenReturn(mock(io.jsonwebtoken.Claims.class));
        when(jwtTokenProvider.getClaims(token).getSubject()).thenReturn(email);
        when(jwtTokenProvider.getClaims(token).get("role", String.class)).thenReturn(role);
        when(userDetailsService.loadUserByUsername(email)).thenReturn(userDetails);
        when(userDetails.getAuthorities()).thenReturn(Arrays.asList());

        // Mock resolveToken to return token
        JwtAuthenticationFilter spyFilter = spy(jwtAuthenticationFilter);
        doReturn(token).when(spyFilter).resolveToken(request);

        // Act
        spyFilter.doFilterInternal(request, response, filterChain);

        // Assert
        verify(filterChain).doFilter(request, response);
        verify(userDetailsService).loadUserByUsername(email);
    }

    @Test
    @DisplayName("TC-SEC-013: doFilterInternal should skip processing for invalid token")
    void doFilterInternal_ShouldSkipForInvalidToken() throws Exception {
        // Arrange
        String token = "invalid-token";

        when(request.getRequestURI()).thenReturn("/api/protected");
        when(jwtTokenProvider.validateToken(token)).thenReturn(false);

        JwtAuthenticationFilter spyFilter = spy(jwtAuthenticationFilter);
        doReturn(token).when(spyFilter).resolveToken(request);

        // Act
        spyFilter.doFilterInternal(request, response, filterChain);

        // Assert
        verify(filterChain).doFilter(request, response);
        verify(jwtTokenProvider, never()).getClaims(anyString());
    }

    @Test
    @DisplayName("TC-SEC-014: doFilterInternal should skip processing when no token")
    void doFilterInternal_ShouldSkipWhenNoToken() throws Exception {
        // Arrange
        when(request.getRequestURI()).thenReturn("/api/protected");

        JwtAuthenticationFilter spyFilter = spy(jwtAuthenticationFilter);
        doReturn(null).when(spyFilter).resolveToken(request);

        // Act
        spyFilter.doFilterInternal(request, response, filterChain);

        // Assert
        verify(filterChain).doFilter(request, response);
        verify(jwtTokenProvider, never()).validateToken(anyString());
    }

    @Test
    @DisplayName("TC-SEC-015: doFilterInternal should renew token when needed")
    void doFilterInternal_ShouldRenewTokenWhenNeeded() throws Exception {
        // Arrange
        String token = "valid-token";
        String email = "test@example.com";
        String role = "PATIENT";
        String renewedToken = "renewed-token";

        io.jsonwebtoken.Claims claims = mock(io.jsonwebtoken.Claims.class);
        when(request.getRequestURI()).thenReturn("/api/protected");
        when(jwtTokenProvider.validateToken(token)).thenReturn(true);
        when(jwtTokenProvider.getClaims(token)).thenReturn(claims);
        when(claims.getSubject()).thenReturn(email);
        when(claims.get("role", String.class)).thenReturn(role);
        when(jwtTokenProvider.needsRenewal(claims)).thenReturn(true);
        when(jwtTokenProvider.refresh(claims)).thenReturn(renewedToken);
        when(userDetailsService.loadUserByUsername(email)).thenReturn(userDetails);
        when(userDetails.getAuthorities()).thenReturn(Arrays.asList());

        JwtAuthenticationFilter spyFilter = spy(jwtAuthenticationFilter);
        doReturn(token).when(spyFilter).resolveToken(request);

        // Act
        spyFilter.doFilterInternal(request, response, filterChain);

        // Assert
        verify(filterChain).doFilter(request, response);
        verify(response).addHeader(eq("Set-Cookie"), anyString());
    }

    @Test
    @DisplayName("TC-SEC-016: DEF-EMG-02: through doFilter, a valid token on an emergency PDF path signs the caller in "
            + "as the token's user")
    void doFilter_SignsInTheTokenUserOnAnEmergencyPath() throws Exception {
        final org.springframework.mock.web.MockHttpServletRequest req =
                new org.springframework.mock.web.MockHttpServletRequest("GET", "/v1/api/emergency/download/VIAL1.pdf");
        req.addHeader("Authorization", "Bearer valid-token");
        final io.jsonwebtoken.Claims claims = mock(io.jsonwebtoken.Claims.class);
        when(claims.getSubject()).thenReturn("patient-one@test.invalid");
        when(jwtTokenProvider.validateToken("valid-token")).thenReturn(true);
        when(jwtTokenProvider.getClaims("valid-token")).thenReturn(claims);
        when(userDetailsService.loadUserByUsername("patient-one@test.invalid")).thenReturn(
                org.springframework.security.core.userdetails.User.withUsername("patient-one@test.invalid")
                        .password("n/a").roles("PATIENT").build());

        // doFilter, not doFilterInternal: shouldNotFilter decides whether the token is read at all.
        jwtAuthenticationFilter.doFilter(req, new org.springframework.mock.web.MockHttpServletResponse(), filterChain);

        verify(jwtTokenProvider).validateToken("valid-token");
        verify(filterChain).doFilter(eq(req), any());
        org.junit.jupiter.api.Assertions.assertEquals("patient-one@test.invalid",
                SecurityContextHolder.getContext().getAuthentication().getName());
    }

    @Test
    @DisplayName("TC-SEC-017: DEF-EMG-02: every path under /v1/api/emergency, and the passport scan path, is filtered")
    void shouldNotFilter_ShouldReturnFalseForTheRestOfTheEmergencyAndPassportPaths() throws Exception {
        for (final String path : Arrays.asList("/v1/api/emergency", "/v1/api/emergency/health",
                "/v1/api/emergency/VIAL999.pdf", "/v1/api/passport", "/v1/api/passport/scan/abc")) {
            when(request.getRequestURI()).thenReturn(path);
            org.junit.jupiter.api.Assertions.assertFalse(jwtAuthenticationFilter.shouldNotFilter(request), path);
        }
    }
}