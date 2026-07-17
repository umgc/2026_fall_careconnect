package com.careconnect.security;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("PermissionAspect")
class PermissionAspectTest {

    @Mock
    private AuthorizationService authorizationService;
    @Mock
    private UserRepository userRepository;

    private PermissionAspect aspect;
    private RequirePermission requirePermission;

    @BeforeEach
    void setUp() {
        aspect = new PermissionAspect();
        ReflectionTestUtils.setField(aspect, "authorizationService", authorizationService);
        ReflectionTestUtils.setField(aspect, "userRepository", userRepository);

        requirePermission = mock(RequirePermission.class);
        lenient().when(requirePermission.value()).thenReturn(Permission.CREATE_TASKS);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private void setAuthenticatedUser(String email) {
        Authentication auth = mock(Authentication.class);
        when(auth.isAuthenticated()).thenReturn(true);
        when(auth.getName()).thenReturn(email);
        SecurityContextHolder.getContext().setAuthentication(auth);
    }

    @Test
    @DisplayName("throws when there is no authentication in the context")
    void throwsWhenNoAuthentication() {
        SecurityContextHolder.clearContext();

        UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> aspect.checkPermission(requirePermission));
        assertEquals("User not authenticated", ex.getMessage());
        verifyNoInteractions(authorizationService);
    }

    @Test
    @DisplayName("throws when the authentication is not authenticated")
    void throwsWhenNotAuthenticated() {
        Authentication auth = mock(Authentication.class);
        when(auth.isAuthenticated()).thenReturn(false);
        SecurityContextHolder.getContext().setAuthentication(auth);

        assertThrows(UnauthorizedException.class,
                () -> aspect.checkPermission(requirePermission));
        verifyNoInteractions(authorizationService);
    }

    @Test
    @DisplayName("throws when the authenticated user is not found")
    void throwsWhenUserNotFound() {
        setAuthenticatedUser("missing@example.com");
        when(userRepository.findByEmail("missing@example.com")).thenReturn(Optional.empty());

        RuntimeException ex = assertThrows(RuntimeException.class,
                () -> aspect.checkPermission(requirePermission));
        assertTrue(ex.getMessage().contains("missing@example.com"));
    }

    @Test
    @DisplayName("delegates to AuthorizationService and passes when permission is granted")
    void passesWhenPermissionGranted() throws Exception {
        User user = mock(User.class);
        setAuthenticatedUser("user@example.com");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));

        assertDoesNotThrow(() -> aspect.checkPermission(requirePermission));
        verify(authorizationService).requirePermission(user, Permission.CREATE_TASKS);
    }

    @Test
    @DisplayName("propagates the UnauthorizedException when permission is denied")
    void propagatesWhenPermissionDenied() throws Exception {
        User user = mock(User.class);
        setAuthenticatedUser("user@example.com");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));
        doThrow(new UnauthorizedException("denied"))
                .when(authorizationService).requirePermission(any(User.class), eq(Permission.CREATE_TASKS));

        UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> aspect.checkPermission(requirePermission));
        assertEquals("denied", ex.getMessage());
    }
}
