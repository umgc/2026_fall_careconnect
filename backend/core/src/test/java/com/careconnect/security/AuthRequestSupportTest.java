package com.careconnect.security;

import com.careconnect.model.User;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class AuthRequestSupportTest {

    @Test
    void requireAuthenticated_withUser_returnsSameUser() throws Exception {
        final User user = new User();

        assertThat(AuthRequestSupport.requireAuthenticated(user)).isSameAs(user);
    }

    @Test
    void requireAuthenticated_nullUser_throwsUnauthorized() {
        assertThatThrownBy(() -> AuthRequestSupport.requireAuthenticated(null))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessage("Missing or invalid authentication token");
    }
}
