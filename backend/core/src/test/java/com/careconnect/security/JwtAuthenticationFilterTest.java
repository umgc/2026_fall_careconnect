package com.careconnect.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
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

    @Test
    @DisplayName("shouldNotFilter should return true for excluded paths")
    void shouldNotFilter_ShouldReturnTrueForExcludedPaths() throws Exception {
        // Test excluded paths
        Arrays.asList("/swagger-ui", "/v3/api-docs", "/v1/api/auth", "/api/v1/auth", "/v1/api/test")
                .forEach(path -> {
                    when(request.getRequestURI()).thenReturn(path);
                    try {
                        assert jwtAuthenticationFilter.shouldNotFilter(request);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                });
    }

    @Test
    @DisplayName("shouldNotFilter should return false for non-excluded paths")
    void shouldNotFilter_ShouldReturnFalseForNonExcludedPaths() throws Exception {
        when(request.getRequestURI()).thenReturn("/api/some-protected-endpoint");
        assert !jwtAuthenticationFilter.shouldNotFilter(request);
    }

    @Test
    @DisplayName("resolveToken should return token from Authorization header")
    void resolveToken_ShouldReturnTokenFromHeader() throws Exception {
        when(request.getHeader("Authorization")).thenReturn("Bearer test-token");
        String token = jwtAuthenticationFilter.resolveToken(request);
        assert token.equals("test-token");
    }

    @Test
    @DisplayName("resolveToken should return token from cookie")
    void resolveToken_ShouldReturnTokenFromCookie() throws Exception {
        Cookie cookie = new Cookie("AUTH", "cookie-token");
        when(request.getCookies()).thenReturn(new Cookie[]{cookie});
        when(request.getHeader("Authorization")).thenReturn(null);
        String token = jwtAuthenticationFilter.resolveToken(request);
        assert token.equals("cookie-token");
    }

    @Test
    @DisplayName("resolveToken should return null when no token present")
    void resolveToken_ShouldReturnNullWhenNoToken() throws Exception {
        when(request.getHeader("Authorization")).thenReturn(null);
        when(request.getCookies()).thenReturn(null);
        String token = jwtAuthenticationFilter.resolveToken(request);
        assert token == null;
    }

    @Test
    @DisplayName("doFilterInternal should process valid token and set authentication")
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
    @DisplayName("doFilterInternal should skip processing for invalid token")
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
    @DisplayName("doFilterInternal should skip processing when no token")
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
    @DisplayName("doFilterInternal should renew token when needed")
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
}