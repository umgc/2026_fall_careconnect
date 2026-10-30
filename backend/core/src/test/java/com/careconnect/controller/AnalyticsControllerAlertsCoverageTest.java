package com.careconnect.controller;

import com.careconnect.dto.WearableReadingIngestionRequest;
import com.careconnect.dto.WearableReadingIngestionResponse;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientCaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.AnalyticsService;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.VitalSampleService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class AnalyticsControllerAlertsCoverageTest {

    @Mock private SecurityUtil securityUtil;
    @Mock private AuthorizationService authorizationService;
    @Mock private UserRepository userRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private CaregiverService caregiverService;
    @Mock private PatientCaregiverRepository caregiverPatientLinkRepository;
    @Mock private AnalyticsService analyticsService;
    @Mock private VitalSampleService vitalSampleService;

    private AnalyticsController controller;
    private User caller;

    @BeforeEach
    void setUp() {
        controller = new AnalyticsController(securityUtil, authorizationService, userRepository,
                patientRepository, caregiverService, caregiverPatientLinkRepository);
        ReflectionTestUtils.setField(controller, "analyticsService", analyticsService);
        ReflectionTestUtils.setField(controller, "vitalSampleService", vitalSampleService);
        caller = User.builder().id(5L).email("u@example.test").role(Role.PATIENT).build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("u@example.test", null, List.of()));
        when(userRepository.findByEmail("u@example.test")).thenReturn(Optional.of(caller));
        Patient patient = new Patient();
        patient.setId(1L);
        patient.setUser(User.builder().id(5L).build());
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(analyticsService.getRecentVitalAlertEvents(anyLong(), anyInt())).thenReturn(List.of());
    }

    @AfterEach
    void tearDown() {
        controller.shutdownSseExecutor();
        SecurityContextHolder.clearContext();
    }

    @Test
    void recentAlertsCheckAccessPerRole() {
        assertThat(controller.recentVitalAlerts(1L, 5).getStatusCode().value()).isEqualTo(200);
        assertThat(controller.recentVitalAlerts(2L, 5).getStatusCode().value()).isEqualTo(404);
        caller.setRole(Role.CAREGIVER);
        when(caregiverService.hasAccessToPatient(5L, 1L)).thenReturn(false);
        assertThat(controller.recentVitalAlerts(1L, 5).getStatusCode().value()).isEqualTo(403);
        caller.setRole(Role.FAMILY_MEMBER);
        when(caregiverService.hasAccessToPatient(5L, 1L)).thenReturn(true);
        assertThat(controller.recentVitalAlerts(1L, 5).getStatusCode().value()).isEqualTo(200);
        caller.setRole(Role.ADMIN);
        assertThat(controller.recentVitalAlerts(1L, 5).getStatusCode().value()).isEqualTo(200);
        when(analyticsService.getRecentVitalAlertEvents(anyLong(), anyInt())).thenThrow(new RuntimeException("db"));
        assertThat(controller.recentVitalAlerts(1L, 5).getStatusCode().value()).isEqualTo(500);
    }

    private static WearableReadingIngestionResponse response(int accepted, int rejected) {
        return WearableReadingIngestionResponse.builder().patientId(1L).acceptedCount(accepted)
                .rejectedCount(rejected).acceptedReadings(List.of()).rejectedReadings(List.of()).build();
    }

    @Test
    void ingestMapsAcceptedAndRejectedCounts() {
        WearableReadingIngestionRequest request = new WearableReadingIngestionRequest(1L, "watch", List.of());
        when(vitalSampleService.ingestWearableReadings(any(), any()))
                .thenReturn(response(0, 2))
                .thenReturn(response(1, 1))
                .thenReturn(response(2, 0));
        assertThat(controller.ingestWearableReadings(request).getStatusCode().value()).isEqualTo(400);
        assertThat(controller.ingestWearableReadings(request).getStatusCode().value()).isEqualTo(207);
        assertThat(controller.ingestWearableReadings(request).getStatusCode().value()).isEqualTo(201);
    }
}
