package com.careconnect.websocket;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.testsupport.fixtures.UserFixtures;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link WebSocketJwtAuthenticator}.
 *
 * <p>The JWT provider and user repository are mocked: these tests cover only the decision of which
 * user (if any) a token resolves to, not JWT signature handling itself.
 */
@ExtendWith(MockitoExtension.class)
class WebSocketJwtAuthenticatorTest {

    @Mock
    private JwtTokenProvider jwtTokenProvider;
    @Mock
    private UserRepository userRepository;

    private WebSocketJwtAuthenticator authenticator;

    @BeforeEach
    void setUp() {
        authenticator = new WebSocketJwtAuthenticator(jwtTokenProvider, userRepository);
    }

    @Test
    void validToken_returnsTokenOwner() {
        // Arrange
        User user = UserFixtures.userWithId(3L);
        when(jwtTokenProvider.validateToken("good")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("good")).thenReturn(user.getEmail());
        when(userRepository.findByEmail(user.getEmail())).thenReturn(Optional.of(user));

        // Act + Assert
        assertThat(authenticator.authenticate("good")).contains(user);
    }

    @Test
    void invalidToken_returnsEmptyWithoutLookingUpUser() {
        when(jwtTokenProvider.validateToken("bad")).thenReturn(false);

        assertThat(authenticator.authenticate("bad")).isEmpty();
        verify(userRepository, never()).findByEmail(any());
    }

    @Test
    void validTokenForUnknownUser_returnsEmpty() {
        when(jwtTokenProvider.validateToken("orphan")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("orphan")).thenReturn("gone@example.com");
        when(userRepository.findByEmail("gone@example.com")).thenReturn(Optional.empty());

        assertThat(authenticator.authenticate("orphan")).isEmpty();
    }

    /**
     * Missing, blank, and non-string tokens (a client could send a number or object) are rejected
     * before the JWT provider is ever called.
     */
    @Test
    void missingBlankOrNonStringToken_returnsEmptyWithoutValidating() {
        assertThat(authenticator.authenticate(null)).isEmpty();
        assertThat(authenticator.authenticate("  ")).isEmpty();
        assertThat(authenticator.authenticate(12345)).isEmpty();
        verify(jwtTokenProvider, never()).validateToken(any());
    }
}
