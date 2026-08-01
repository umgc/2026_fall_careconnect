package com.careconnect.security;

import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import java.time.Duration;
import java.security.Key;
import java.time.Instant;
import java.util.Date;

@Component
public class JwtTokenProvider {

    private static final Duration SLIDING_WINDOW    = Duration.ofHours(3);
    private static final Duration RENEW_THRESHOLD   = Duration.ofMinutes(5);
    private static final String   ISSUER            = "careconnect";

    private final Key key;
    private final Duration accessTtl;

    public JwtTokenProvider(@Value("${security.jwt.secret}") String secretBase64,
                           @Value("${jwt.expiration.ms:10800000}") long expirationMs) {
        this.key = Keys.hmacShaKeyFor(java.util.Base64.getUrlDecoder().decode(secretBase64.trim()));
        this.accessTtl = Duration.ofMillis(expirationMs);
    }

    public String createToken(String email, Role role) {
        return buildToken(email, role, accessTtl);
    }

    private String buildToken(String email, Role role, Duration ttl) {
        Instant now = Instant.now();
        return Jwts.builder()
                .setIssuer(ISSUER)
                .setSubject(email)
                .claim("role", role.name())
                .setIssuedAt(Date.from(now))
                .setExpiration(Date.from(now.plus(ttl)))
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            System.err.println("[JWT DEBUG] Invalid token: " + e.getMessage());
            System.err.println("[JWT DEBUG] Secret (base64): " + java.util.Base64.getEncoder().encodeToString(key.getEncoded()));
            e.printStackTrace();
            return false;
        }
    }

    public String getUsername(String token) {
        return Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token).getBody().getSubject();
    }

    public Role getRole(String token) {
        String role = Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token).getBody().get("role", String.class);
        return Role.valueOf(role);
    }

    public boolean needsRenewal(Claims claims) {
        Instant exp = claims.getExpiration().toInstant();
        Instant now = Instant.now();
        return exp.minus(RENEW_THRESHOLD).isBefore(now)        
                && claims.getIssuedAt().toInstant()
                         .plus(SLIDING_WINDOW)
                         .isAfter(now);                               
    }

    private Jws<Claims> parse(String token) {
        return Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token);
    }

    public String refresh(Claims oldClaims) {
        String email = oldClaims.getSubject();
        Role   role  = Role.valueOf(oldClaims.get("role", String.class));
        return buildToken(email, role, accessTtl);
    }

    public Claims getClaims(String token) {
        return Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token).getBody();
    }

    public String getEmailFromToken(String token) {
        return getUsername(token); 
    }
}