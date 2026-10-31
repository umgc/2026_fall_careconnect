package com.careconnect.controller;

import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.InviteTokenService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class InviteControllerCoverageTest {

    @Mock private InviteTokenService inviteTokenService;
    @Mock private UserRepository userRepository;
    @InjectMocks private InviteController controller;

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    private void authenticate(String principal) {
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(principal, null, List.of()));
    }

    @Test
    void endpointsResolveCallerAndForwardIp() {
        User caregiver = User.builder().id(3L).email("cg@example.test").role(Role.CAREGIVER).build();
        when(userRepository.findByEmail("cg@example.test")).thenReturn(Optional.of(caregiver));
        authenticate("cg@example.test");
        MockHttpServletRequest req = new MockHttpServletRequest();
        req.addHeader("X-Forwarded-For", "203.0.113.5, 10.0.0.1");

        assertThat(controller.createInvite(1L, null, req).getStatusCode().value()).isEqualTo(201);
        assertThat(controller.previewInvite("tok", new MockHttpServletRequest()).getStatusCode().value())
                .isEqualTo(200);
        assertThat(controller.acceptInvite("tok", req).getStatusCode().value()).isEqualTo(200);
        assertThat(controller.revokeInvite(1L, 2L, null, req).getStatusCode().value()).isEqualTo(204);

        caregiver.setRole(Role.FAMILY_MEMBER);
        assertThat(controller.createInvite(1L, null, req).getStatusCode().value()).isEqualTo(403);
        assertThat(controller.revokeInvite(1L, 2L, null, req).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void numericPrincipalFallsBackToIdLookup() {
        when(userRepository.findByEmail(anyString())).thenReturn(Optional.empty());
        when(userRepository.findById(7L)).thenReturn(Optional.of(User.builder().id(7L).role(Role.PATIENT).build()));
        authenticate("7");
        assertThat(controller.acceptInvite("tok", new MockHttpServletRequest()).getStatusCode().value())
                .isEqualTo(200);

        authenticate("8");
        assertThatThrownBy(() -> controller.acceptInvite("tok", new MockHttpServletRequest()))
                .isInstanceOf(AppException.class);
        authenticate("not-a-number");
        assertThatThrownBy(() -> controller.acceptInvite("tok", new MockHttpServletRequest()))
                .isInstanceOf(AppException.class);
        SecurityContextHolder.clearContext();
        assertThatThrownBy(() -> controller.acceptInvite("tok", new MockHttpServletRequest()))
                .isInstanceOf(AppException.class);
    }
}
