package com.careconnect.testsupport.fixtures;

import com.careconnect.model.User;
import com.careconnect.security.Role;

/**
 * Shared user fixture builders for backend unit tests.
 *
 * <p>
 * Websocket handler tests resolve a {@link User} from a mocked JWT authenticator and only care
 * about the user's id, so the remaining fields are stable placeholders.
 * </p>
 */
public final class UserFixtures {

    private UserFixtures() {
        // Utility class
    }

    /**
     * Returns a patient-role user with the given id and an email derived from it.
     *
     * <p>
     * Use when a test needs distinct authenticated users that differ only by id.
     * </p>
     */
    public static User userWithId(Long id) {
        return User.builder()
                .id(id)
                .name("User " + id)
                .email("user" + id + "@example.com")
                .role(Role.PATIENT)
                .build();
    }
}
