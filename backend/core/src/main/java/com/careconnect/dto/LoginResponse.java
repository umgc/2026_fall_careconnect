package com.careconnect.dto;

import com.careconnect.security.Role;
import lombok.Builder;

@Builder
public record LoginResponse(
        long id,
        String email,
        Role role,
        String token,
        Long patientId,
        Long caregiverId,
        String name,
        String status,
        boolean emailVerified
) {

    public static LoginResponseBuilder builder() {
        return new LoginResponseBuilder();
    }

    public static class LoginResponseBuilder {
        private long id;
        private String email;
        private Role role;
        private String token;
        private Long patientId;
        private Long caregiverId;
        private String name;
        private String status;
        private boolean emailVerified;

        public LoginResponseBuilder name(String name) {
            this.name = name;
            return this;
        }

        public LoginResponseBuilder status(String status) {
            this.status = status;
            return this;
        }

        public LoginResponseBuilder id(long id) {
            this.id = id;
            return this;
        }

        public LoginResponseBuilder patientId(Long patientId) {
            this.patientId = patientId;
            return this;
        }

        public LoginResponseBuilder caregiverId(Long caregiverId) {
            this.caregiverId = caregiverId;
            return this;
        }

        public LoginResponseBuilder email(String email) {
            this.email = email;
            return this;
        }

        public LoginResponseBuilder role(Role role) {
            this.role = role;
            return this;
        }

        public LoginResponseBuilder token(String token) {
            this.token = token;
            return this;
        }

        public LoginResponseBuilder emailVerified(boolean emailVerified) {
            this.emailVerified = emailVerified;
            return this;
        }

        public LoginResponse build() {
            return new LoginResponse(id, email, role, token, patientId, caregiverId, name, status, emailVerified);
        }
    }
}