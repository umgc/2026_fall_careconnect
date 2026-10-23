package com.careconnect.websocket;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Resolves the {@link User} behind a JWT sent in a websocket {@code authenticate} message.
 *
 * <p>Websocket channels authenticate in-band (the first message carries the token) because browsers
 * cannot set headers on the upgrade request. Every channel must derive the user from the token and
 * never trust a client-supplied user id.
 */
@Component
@RequiredArgsConstructor
public class WebSocketJwtAuthenticator {

    private final JwtTokenProvider jwtTokenProvider;
    private final UserRepository userRepository;

    /**
     * Returns the user the token belongs to, or empty when the token is missing, invalid, or
     * belongs to no user.
     *
     * @param token raw JWT from the client message (may be null)
     * @return the authenticated user, if any
     */
    public Optional<User> authenticate(final Object token) {
        if (!(token instanceof String raw) || raw.isBlank() || !jwtTokenProvider.validateToken(raw)) {
            return Optional.empty();
        }
        return userRepository.findByEmail(jwtTokenProvider.getEmailFromToken(raw));
    }
}
