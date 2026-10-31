package com.careconnect.controller;

import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.MoodService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class MoodControllerAccessCoverageTest {

    @Mock private MoodService moodService;
    @Mock private UserRepository userRepository;
    @Mock private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock private FamilyMemberService familyMemberService;
    @InjectMocks private MoodController controller;

    private final User caller = User.builder().id(5L).email("m@example.test").role(Role.PATIENT).build();

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("m@example.test", null, List.of()));
        when(userRepository.findByEmail("m@example.test")).thenReturn(Optional.of(caller));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void writeAndReadAccessPerRole() throws Exception {
        Map<String, Object> blankLabel = new HashMap<>();
        blankLabel.put("score", 4);
        blankLabel.put("label", " ");
        assertThat(controller.saveMood(5L, blankLabel).getStatusCode().value()).isEqualTo(200);
        assertThatThrownBy(() -> controller.saveMood(5L, Map.of("score", "x"))).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> controller.getMoods(6L)).isInstanceOf(AppException.class);

        caller.setRole(Role.CAREGIVER);
        assertThatThrownBy(() -> controller.saveMood(6L, blankLabel)).isInstanceOf(AppException.class);
        when(caregiverPatientLinkService.hasAccessToPatient(5L, 6L)).thenReturn(false);
        assertThatThrownBy(() -> controller.getMoods(6L)).isInstanceOf(AppException.class);
        when(caregiverPatientLinkService.hasAccessToPatient(5L, 7L)).thenReturn(true);
        assertThat(controller.getMoods(7L).getStatusCode().value()).isEqualTo(200);

        caller.setRole(Role.FAMILY_MEMBER);
        assertThatThrownBy(() -> controller.saveMood(6L, blankLabel)).isInstanceOf(AppException.class);
        when(familyMemberService.hasAccessToPatient(5L, 6L)).thenReturn(false);
        assertThatThrownBy(() -> controller.getMoods(6L)).isInstanceOf(AppException.class);
        when(familyMemberService.hasAccessToPatient(5L, 7L)).thenReturn(true);
        assertThat(controller.getMoods(7L).getStatusCode().value()).isEqualTo(200);

        caller.setRole(Role.ADMIN);
        assertThat(controller.getMoods(7L).getStatusCode().value()).isEqualTo(200);
    }
}
