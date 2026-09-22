package com.careconnect.security;

import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.*;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.*;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.util.Arrays;
import java.util.List;

@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(JwtAuthenticationFilter.class);
    private static final String COOKIE_NAME = "AUTH";

    // Paths that should be excluded from JWT authentication
    private static final List<String> EXCLUDED_PATHS = Arrays.asList(
            "/swagger-ui",
            "/v3/api-docs",
            "/swagger-resources",
            "/webjars",
            "/v1/api/auth",
            "/api/v1/auth",
            "/v1/api/test",
            "/v1/api/email-test",
            "/v1/api/emergency"
    );
    private static final Logger logger = LoggerFactory.getLogger(JwtAuthenticationFilter.class);
    private final JwtTokenProvider jwt;
    private final UserDetailsService uds;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) throws ServletException {
        String path = request.getRequestURI();
        return EXCLUDED_PATHS.stream().anyMatch(path::startsWith);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req,
                                    HttpServletResponse res,
                                    FilterChain chain)
            throws ServletException, IOException {

        String requestURI = req.getRequestURI();
        log.debug("Processing JWT authentication for: {}", requestURI);

        /* ---------- 1. Find token (header or cookie) --------------------- */
        String token = resolveToken(req);
        log.debug("Resolved token: {}", token != null ? "present" : "null");

        /* ---------- 2. Validate & build Authentication ------------------- */
        if (token != null && jwt.validateToken(token)) {
            log.debug("Token is valid, processing authentication");
            Claims claims = jwt.getClaims(token);
            String email = claims.getSubject();
            String role = claims.get("role", String.class);
            log.debug("Token email subject: {}, role: {}", email, role);

            // Use role-specific user loading for more precise authentication  
            UserDetails userDetails;
            if (role != null && uds instanceof UserDetailsServiceImpl) {
                userDetails = ((UserDetailsServiceImpl) uds).loadUserByEmailAndRole(email, role);
            } else {
                // Fallback to email-only lookup (may have ambiguity issues)
                userDetails = uds.loadUserByUsername(email);
            }

            UsernamePasswordAuthenticationToken auth =
                    new UsernamePasswordAuthenticationToken(
                            userDetails, null, userDetails.getAuthorities());
            auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(req));
            SecurityContextHolder.getContext().setAuthentication(auth);
            log.debug("Authentication set for user: {} with role: {}", email, role);

            /* ---------- 3. Silent renew (<5 min left) -------------------- */
            if (jwt.needsRenewal(claims)) {
                String renewed = jwt.refresh(claims);
                ResponseCookie cookie = ResponseCookie.from(COOKIE_NAME, renewed)
                        .httpOnly(true).secure(true).sameSite("Lax").path("/")
                        .maxAge(Duration.ofHours(3))            // sliding-window cap
                        .build();
                res.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());
                log.debug("Token renewed for user: {}", email);
            }
        } else {
            if (token != null) {
                log.warn("Invalid token provided");
            } else {
                log.debug("No token found in request");
            }
        }

        chain.doFilter(req, res);
    }

    String resolveToken(HttpServletRequest req) {
        // a) Bearer header
        String header = req.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            return header.substring(7);
        }
        // b) HttpOnly cookie
        if (req.getCookies() != null) {
            return Arrays.stream(req.getCookies())
                    .filter(c -> COOKIE_NAME.equals(c.getName()))
                    .findFirst()
                    .map(Cookie::getValue)
                    .orElse(null);
        }
        return null;
    }
}
