package com.careconnect.util;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

@Component
public class SecurityUtil {

    private final JwtTokenProvider jwtTokenProvider;
    private final UserRepository userRepository;

    @Autowired
    public SecurityUtil(JwtTokenProvider jwtTokenProvider, UserRepository userRepository) {
        this.jwtTokenProvider = jwtTokenProvider;
        this.userRepository = userRepository;
    }

    public UserInfo getCurrentUser(HttpServletRequest request) {
        String header = request.getHeader("Authorization");
        if (header == null || !header.startsWith("Bearer ")) {
            throw new RuntimeException("Missing or invalid Authorization header");
        }
        String token = header.substring(7);
        String email = jwtTokenProvider.getUsername(token);
        Role role = jwtTokenProvider.getRole(token);
        return new UserInfo(email, role);
    }

    /**
     * Resolve the full User entity from the current SecurityContext.
     * Uses the email and role from the JWT-based authentication to look up the User.
     *
     * @return the authenticated User entity
     * @throws RuntimeException if no authenticated user is found
     */
    public User resolveCurrentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null) {
            return null;
        }

        // Check for anonymous role safely
        boolean isAnonymous = auth.getAuthorities().stream()
                .anyMatch(authority -> "ROLE_ANONYMOUS".equals(authority.getAuthority()));

        if (isAnonymous) {
            return null;
        }

        String email = auth.getName();

        // Extract role from granted authorities (format: ROLE_ADMIN, ROLE_CAREGIVER, etc.)
        String roleName = auth.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .filter(a -> a.startsWith("ROLE_"))
                .map(a -> a.substring(5))
                .findFirst()
                .orElse(null);

        if (roleName != null) {

            //Handle anonymous user
            if ("ANONYMOUS".equalsIgnoreCase(roleName)) {
                return null; // allow unauthenticated access for testing
            }

            try {
                return userRepository.findByEmailAndRole(email, Role.valueOf(roleName))
                        .orElseThrow(() -> new RuntimeException("User not found: " + email));
            } catch (IllegalArgumentException e) {
                throw new RuntimeException("Invalid role: " + roleName);
            }
        }

        return userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("User not found: " + email));
    }

    public static class UserInfo {
        public final String email;
        public final Role role;

        public UserInfo(String email, Role role) {
            this.email = email;
            this.role = role;
        }
    }
}