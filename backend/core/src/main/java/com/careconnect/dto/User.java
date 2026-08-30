package com.careconnect.dto;

import lombok.Getter;
import lombok.Setter;

@Setter
@Getter
public class User {
    private Long id;
    private String email;
    private String password;
    private boolean emailVerified;
    private com.careconnect.security.Role role;
    private String status;

    public boolean isActive() {
        return "ACTIVE".equalsIgnoreCase(status);
    }

}