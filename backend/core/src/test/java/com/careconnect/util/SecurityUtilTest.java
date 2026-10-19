package com.careconnect.util;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SecurityUtilTest {

    @Mock
    JwtTokenProvider jwtTokenProvider;
    @Mock
    UserRepository userRepository;
    @Mock
    HttpServletRequest request;

    @InjectMocks
    SecurityUtil securityUtil;

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    // ─── getCurrentUser() ─────────────────────────────────────────────────────

    @Test
    void getCurrentUser_nullAuthorizationHeader_throwsRuntimeException() {
        when(request.getHeader("Authorization")).thenReturn(null);

        assertThatThrownBy(() -> securityUtil.getCurrentUser(request))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Missing or invalid Authorization header");
    }

    @Test
    void getCurrentUser_headerWithoutBearerPrefix_throwsRuntimeException() {
        when(request.getHeader("Authorization")).thenReturn("Basic abc123");

        assertThatThrownBy(() -> securityUtil.getCurrentUser(request))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Missing or invalid Authorization header");
    }

    @Test
    void getCurrentUser_validBearerToken_returnsUserInfo() {
        final String token = "valid-jwt-token";
        when(request.getHeader("Authorization")).thenReturn("Bearer " + token);
        when(jwtTokenProvider.getUsername(token)).thenReturn("user@example.com");
        when(jwtTokenProvider.getRole(token)).thenReturn(Role.PATIENT);

        final SecurityUtil.UserInfo info = securityUtil.getCurrentUser(request);

        assertThat(info).isNotNull();
        assertThat(info.email).isEqualTo("user@example.com");
        assertThat(info.role).isEqualTo(Role.PATIENT);
    }

    // ─── resolveCurrentUser() ─────────────────────────────────────────────────

    @Test
    void resolveCurrentUser_nullAuth_returnsNull() {
        final SecurityContext ctx = mock(SecurityContext.class);
        when(ctx.getAuthentication()).thenReturn(null);
        SecurityContextHolder.setContext(ctx);

        assertThat(securityUtil.resolveCurrentUser()).isNull();
    }

    @Test
    void resolveCurrentUser_notAuthenticated_throwsRuntimeException() {
        final SecurityContext ctx = mock(SecurityContext.class);
        final Authentication auth = mock(Authentication.class);
        when(ctx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(ctx);

        assertThatThrownBy(() -> securityUtil.resolveCurrentUser())
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("User not found: null");
    }

    @Test
    void resolveCurrentUser_withRoleAuthority_findsUserByEmailAndRole() {
        final SecurityContext ctx = mock(SecurityContext.class);
        final Authentication auth = mock(Authentication.class);
        when(auth.getName()).thenReturn("admin@test.com");

        final List<SimpleGrantedAuthority> authorities = List.of(new SimpleGrantedAuthority("ROLE_ADMIN"));
        doReturn(authorities).when(auth).getAuthorities();

        when(ctx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(ctx);

        final User expectedUser = User.builder().email("admin@test.com").role(Role.ADMIN).build();
        when(userRepository.findByEmailAndRole("admin@test.com", Role.ADMIN))
                .thenReturn(Optional.of(expectedUser));

        final User result = securityUtil.resolveCurrentUser();
        assertThat(result.getEmail()).isEqualTo("admin@test.com");
    }

    @Test
    void resolveCurrentUser_withRoleAuthority_userNotFound_throwsRuntimeException() {
        final SecurityContext ctx = mock(SecurityContext.class);
        final Authentication auth = mock(Authentication.class);
        when(auth.getName()).thenReturn("missing@test.com");

        final List<SimpleGrantedAuthority> authorities = List.of(new SimpleGrantedAuthority("ROLE_CAREGIVER"));
        doReturn(authorities).when(auth).getAuthorities();

        when(ctx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(ctx);

        when(userRepository.findByEmailAndRole("missing@test.com", Role.CAREGIVER))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> securityUtil.resolveCurrentUser())
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("User not found: missing@test.com");
    }

    @Test
    void resolveCurrentUser_withoutRoleAuthority_findsUserByEmail() {
        final SecurityContext ctx = mock(SecurityContext.class);
        final Authentication auth = mock(Authentication.class);
        when(auth.getName()).thenReturn("user@test.com");

        final List<SimpleGrantedAuthority> authorities = List.of(new SimpleGrantedAuthority("SCOPE_read"));
        doReturn(authorities).when(auth).getAuthorities();

        when(ctx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(ctx);

        final User expectedUser = User.builder().email("user@test.com").role(Role.PATIENT).build();
        when(userRepository.findByEmail("user@test.com"))
                .thenReturn(Optional.of(expectedUser));

        final User result = securityUtil.resolveCurrentUser();
        assertThat(result.getEmail()).isEqualTo("user@test.com");
    }

    @Test
    void resolveCurrentUser_withoutRoleAuthority_userNotFound_throwsRuntimeException() {
        final SecurityContext ctx = mock(SecurityContext.class);
        final Authentication auth = mock(Authentication.class);
        when(auth.getName()).thenReturn("gone@test.com");

        final List<SimpleGrantedAuthority> authorities = List.of();
        doReturn(authorities).when(auth).getAuthorities();

        when(ctx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(ctx);

        when(userRepository.findByEmail("gone@test.com"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> securityUtil.resolveCurrentUser())
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("User not found: gone@test.com");
    }

    // ─── UserInfo inner class ─────────────────────────────────────────────────

    @Test
    void userInfo_constructorSetsFields() {
        final SecurityUtil.UserInfo info = new SecurityUtil.UserInfo("admin@example.com", Role.ADMIN);

        assertThat(info.email).isEqualTo("admin@example.com");
        assertThat(info.role).isEqualTo(Role.ADMIN);
    }
}
