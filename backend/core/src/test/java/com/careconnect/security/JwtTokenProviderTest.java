package com.careconnect.security;

import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

class JwtTokenProviderTest {

    private final String testSecret = "dGVzdC1zZWNyZXQtZm9yLWp3dC10b2tlbi1wcm92aWRlci10ZXN0aW5nMTIzNDU2Nzg5MDEyMzQ1Njc4OTA="; // base64 encoded 256-bit key
    private final long testExpirationMs = 3600000; // 1 hour
    private JwtTokenProvider jwtTokenProvider;

    @BeforeEach
    void setUp() throws Exception {
        jwtTokenProvider = new JwtTokenProvider(testSecret, testExpirationMs);
    }

    @Test
    @DisplayName("Should create valid token with correct claims")
    void createToken_ShouldCreateValidToken() throws Exception {
        // Given
        String email = "test@example.com";
        Role role = Role.PATIENT;

        // When
        String token = jwtTokenProvider.createToken(email, role);

        // Then
        assertNotNull(token);
        assertTrue(jwtTokenProvider.validateToken(token));
        assertEquals(email, jwtTokenProvider.getUsername(token));
        assertEquals(role, jwtTokenProvider.getRole(token));
    }

    @Test
    @DisplayName("Should validate valid token successfully")
    void validateToken_ShouldReturnTrueForValidToken() throws Exception {
        // Given
        String email = "user@test.com";
        Role role = Role.ADMIN;
        String token = jwtTokenProvider.createToken(email, role);

        // When & Then
        assertTrue(jwtTokenProvider.validateToken(token));
    }

    @Test
    @DisplayName("Should reject invalid token")
    void validateToken_ShouldReturnFalseForInvalidToken() throws Exception {
        // Given
        String invalidToken = "invalid.jwt.token";

        // When & Then
        assertFalse(jwtTokenProvider.validateToken(invalidToken));
    }

    @Test
    @DisplayName("Should reject null or empty token")
    void validateToken_ShouldReturnFalseForNullOrEmptyToken() throws Exception {
        // When & Then
        assertFalse(jwtTokenProvider.validateToken(null));
        assertFalse(jwtTokenProvider.validateToken(""));
        assertFalse(jwtTokenProvider.validateToken("   "));
    }

    @Test
    @DisplayName("Should extract username from token")
    void getUsername_ShouldReturnCorrectUsername() throws Exception {
        // Given
        String email = "patient@example.com";
        Role role = Role.PATIENT;
        String token = jwtTokenProvider.createToken(email, role);

        // When
        String extractedUsername = jwtTokenProvider.getUsername(token);

        // Then
        assertEquals(email, extractedUsername);
    }

    @Test
    @DisplayName("Should extract role from token")
    void getRole_ShouldReturnCorrectRole() throws Exception {
        // Given
        String email = "caregiver@test.com";
        Role role = Role.CAREGIVER;
        String token = jwtTokenProvider.createToken(email, role);

        // When
        Role extractedRole = jwtTokenProvider.getRole(token);

        // Then
        assertEquals(role, extractedRole);
    }

    @Test
    @DisplayName("Should extract claims from token")
    void getClaims_ShouldReturnClaims() throws Exception {
        // Given
        String email = "admin@test.com";
        Role role = Role.ADMIN;
        String token = jwtTokenProvider.createToken(email, role);

        // When
        Claims claims = jwtTokenProvider.getClaims(token);

        // Then
        assertNotNull(claims);
        assertEquals(email, claims.getSubject());
        assertEquals(role.name(), claims.get("role"));
        assertEquals("careconnect", claims.getIssuer());
        assertNotNull(claims.getIssuedAt());
        assertNotNull(claims.getExpiration());
    }

    @Test
    @DisplayName("getEmailFromToken should return same as getUsername")
    void getEmailFromToken_ShouldReturnSameAsGetUsername() throws Exception {
        // Given
        String email = "family@test.com";
        Role role = Role.FAMILY_MEMBER;
        String token = jwtTokenProvider.createToken(email, role);

        // When
        String emailFromToken = jwtTokenProvider.getEmailFromToken(token);
        String usernameFromToken = jwtTokenProvider.getUsername(token);

        // Then
        assertEquals(emailFromToken, usernameFromToken);
        assertEquals(email, emailFromToken);
    }

    @Test
    @DisplayName("Should determine if token needs renewal when close to expiration")
    void needsRenewal_ShouldReturnTrueWhenCloseToExpiration() throws Exception {
        // Given - create a token that expires in 10 seconds
        JwtTokenProvider shortLivedProvider = new JwtTokenProvider(testSecret, 10000); // 10 seconds
        String email = "test@example.com";
        Role role = Role.PATIENT;
        String token = shortLivedProvider.createToken(email, role);

        // Get claims immediately
        Claims claims = shortLivedProvider.getClaims(token);

        // When - check if needs renewal (should be true since exp - 5min < now)
        boolean needsRenewal = shortLivedProvider.needsRenewal(claims);

        // Then
        assertTrue(needsRenewal, "Token should need renewal when close to expiration");
    }

    @Test
    @DisplayName("Should not need renewal for fresh token")
    void needsRenewal_ShouldReturnFalseForFreshToken() throws Exception {
        // Given
        String email = "fresh@test.com";
        Role role = Role.PATIENT;
        String token = jwtTokenProvider.createToken(email, role);
        Claims claims = jwtTokenProvider.getClaims(token);

        // When
        boolean needsRenewal = jwtTokenProvider.needsRenewal(claims);

        // Then
        assertFalse(needsRenewal);
    }

    @Test
    @DisplayName("Should refresh token with new timestamps")
    void refresh_ShouldCreateNewTokenWithUpdatedExpiration() throws Exception {
        // Given
        String email = "refresh@test.com";
        Role role = Role.ADMIN;
        String originalToken = jwtTokenProvider.createToken(email, role);
        Claims originalClaims = jwtTokenProvider.getClaims(originalToken);

        // Wait long enough to cross a seconds boundary (JWT uses second precision)
        try {
            Thread.sleep(1100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }


        // When
        String refreshedToken = jwtTokenProvider.refresh(originalClaims);

        // Then
        assertNotNull(refreshedToken);
        assertTrue(jwtTokenProvider.validateToken(refreshedToken));
        assertEquals(email, jwtTokenProvider.getUsername(refreshedToken));
        assertEquals(role, jwtTokenProvider.getRole(refreshedToken));

        // Check that it's a valid refreshed token
        Claims refreshedClaims = jwtTokenProvider.getClaims(refreshedToken);
        assertNotNull(refreshedClaims.getIssuedAt());
        assertNotNull(refreshedClaims.getExpiration());

        // The refreshed token should have a later expiration
        assertTrue(refreshedClaims.getExpiration().after(originalClaims.getExpiration()),
                "Refreshed token should have a later expiration than the original token");

        // Token string should now differ
        assertNotEquals(originalToken, refreshedToken,
                "Refreshed token should be a new token");


    }

    @Test
    @DisplayName("Should handle all role types correctly")
    void createToken_ShouldHandleAllRoleTypes() throws Exception {
        String email = "test@example.com";

        for (Role role : Role.values()) {
            String token = jwtTokenProvider.createToken(email, role);
            assertNotNull(token);
            assertTrue(jwtTokenProvider.validateToken(token));
            assertEquals(role, jwtTokenProvider.getRole(token));
        }
    }

    @Test
    @DisplayName("Should reject token with wrong secret")
    void validateToken_ShouldRejectTokenWithWrongSecret() throws Exception {
        // Given - create token with one provider
        String email = "test@example.com";
        Role role = Role.PATIENT;
        String token = jwtTokenProvider.createToken(email, role);

        // Create another provider with different secret (256-bit)
        String differentSecret = "ZGlmZmVyZW50LXNlY3JldC1mb3ItdGVzdGluZzEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU="; // base64 encoded 256-bit key
        JwtTokenProvider differentProvider = new JwtTokenProvider(differentSecret, testExpirationMs);

        // When & Then
        assertFalse(differentProvider.validateToken(token));
    }

    @Test
    @DisplayName("Token should expire after specified time")
    void validateToken_ShouldRejectExpiredToken() throws InterruptedException {
        // Given - create provider with very short expiration
        JwtTokenProvider shortProvider = new JwtTokenProvider(testSecret, 1000); // 1 second
        String email = "expire@test.com";
        Role role = Role.PATIENT;
        String token = shortProvider.createToken(email, role);

        // Wait for expiration
        Thread.sleep(1500);

        // When & Then
        assertFalse(shortProvider.validateToken(token));
    }
}