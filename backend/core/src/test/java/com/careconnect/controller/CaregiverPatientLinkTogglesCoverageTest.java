package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class CaregiverPatientLinkTogglesCoverageTest {

    @Mock private CaregiverPatientLinkService linkService;
    @Mock private UserRepository userRepository;
    @InjectMocks private CaregiverPatientLinkController controller;

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void togglesParseEnabledFlagFromBooleanOrString() {
        User cg = User.builder().id(3L).email("cg@example.test").role(Role.CAREGIVER).build();
        when(userRepository.findByEmail("cg@example.test")).thenReturn(Optional.of(cg));
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("cg@example.test", null, List.of()));

        assertThat(controller.setPatientVideoCalls(1L, Map.of("enabled", true)).getStatusCode().value())
                .isEqualTo(200);
        assertThat(controller.setPatientVideoCalls(1L, Map.of("enabled", "false")).getStatusCode().value())
                .isEqualTo(200);
        assertThat(controller.setPatientMessaging(2L, Map.of("enabled", false)).getStatusCode().value())
                .isEqualTo(200);
        assertThat(controller.setPatientMessaging(2L, Map.of("enabled", "true")).getStatusCode().value())
                .isEqualTo(200);
        verify(linkService).setPatientVideoCallsEnabled(eq(1L), eq(true), eq(3L), eq(Role.CAREGIVER));
        verify(linkService).setPatientMessagingEnabled(eq(2L), eq(true), eq(3L), eq(Role.CAREGIVER));
    }
}
