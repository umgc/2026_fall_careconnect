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
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
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

        UnauthorizedException ex = assertThrows(UnauthorizedException.class,
                () -> aspect.checkPermission(requirePermission));
        assertEquals("Authenticated user could not be resolved", ex.getMessage());
    }

    @Test
    @DisplayName("delegates to AuthorizationService and passes when permission is granted")
    void passesWhenPermissionGranted() throws Exception {
        User user = mock(User.class);
        setAuthenticatedUser("user@example.com");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));
        when(authorizationService.hasPermission(user, Permission.CREATE_TASKS)).thenReturn(true);

        assertDoesNotThrow(() -> aspect.checkPermission(requirePermission));
        verify(authorizationService).hasPermission(user, Permission.CREATE_TASKS);
    }

    @Test
    @DisplayName("uses AccessDeniedException when an authenticated user lacks permission")
    void propagatesWhenPermissionDenied() throws Exception {
        User user = mock(User.class);
        setAuthenticatedUser("user@example.com");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));
        when(authorizationService.hasPermission(user, Permission.CREATE_TASKS)).thenReturn(false);

        AccessDeniedException ex = assertThrows(AccessDeniedException.class,
                () -> aspect.checkPermission(requirePermission));
        assertEquals("Required permission is not granted", ex.getMessage());
    }
}