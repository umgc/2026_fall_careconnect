package com.careconnect.security;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
@Slf4j
public class TokenHashService {

    @Autowired
    private PasswordEncoder passwordEncoder;

    /**
     * Hash a refresh token before storing in database
     */
    public String hashToken(String token) {
        if (token == null || token.isBlank()) {
            return null;
        }
        String hashed = passwordEncoder.encode(token);
        log.debug("✅ Token hashed successfully");
        return hashed;
    }

    /**
     * Verify a plain text token against the stored hash
     */
    public boolean verifyToken(String plainToken, String hashedToken) {
        if (plainToken == null || hashedToken == null) {
            log.warn("⚠️ Token or hash is null");
            return false;
        }

        boolean matches = passwordEncoder.matches(plainToken, hashedToken);
        if (matches) {
            log.debug("✅ Token verified successfully");
        } else {
            log.warn("❌ Token verification failed");
        }
        return matches;
    }
}