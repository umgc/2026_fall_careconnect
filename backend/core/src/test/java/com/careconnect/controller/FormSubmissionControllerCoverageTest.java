package com.careconnect.controller;

import com.careconnect.dto.FormSubmissionRequest;
import com.careconnect.model.User;
import com.careconnect.model.UserFile;
import com.careconnect.model.forms.FormSubmission;
import com.careconnect.model.forms.FormType;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.FormSubmissionService;
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

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class FormSubmissionControllerCoverageTest {

    @Mock private FormSubmissionService submissionService;
    @Mock private UserRepository userRepository;
    @Mock private CaregiverService caregiverService;

    private FormSubmissionController controller;
    private User caregiver;

    @BeforeEach
    void setUp() {
        controller = new FormSubmissionController(submissionService, userRepository, caregiverService);
        caregiver = User.builder().id(3L).email("cg@example.test").role(Role.CAREGIVER).build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("cg@example.test", null, List.of()));
        when(userRepository.findByEmail("cg@example.test")).thenReturn(Optional.of(caregiver));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static FormSubmissionRequest request(FormType type, boolean confirmed, Long patientId) {
        FormSubmissionRequest r = new FormSubmissionRequest();
        r.setFormType(type);
        r.setConfirmed(confirmed);
        r.setPatientId(patientId);
        r.setFieldValues(Map.of("a.b", "c"));
        return r;
    }

    @Test
    void submitCoversValidationAndOutcomes() {
        assertThat(controller.submit(request(null, true, null)).getStatusCode().value()).isEqualTo(400);
        assertThat(controller.submit(request(FormType.W4, false, null)).getStatusCode().value()).isEqualTo(400);

        when(caregiverService.hasAccessToPatient(3L, 9L)).thenReturn(false);
        assertThat(controller.submit(request(FormType.W4, true, 9L)).getStatusCode().value()).isEqualTo(403);
        when(caregiverService.hasAccessToPatient(3L, 8L)).thenThrow(new RuntimeException("lookup"));
        assertThat(controller.submit(request(FormType.W4, true, 8L)).getStatusCode().value()).isEqualTo(403);

        when(caregiverService.hasAccessToPatient(3L, 7L)).thenReturn(true);
        FormSubmission saved = FormSubmission.builder().id(1L).formType(FormType.W4).formVersion("2026")
                .submittedAt(LocalDateTime.now()).build();
        when(submissionService.submit(any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(new FormSubmissionService.SubmissionResult(saved, List.of()))
                .thenReturn(new FormSubmissionService.SubmissionResult(null, List.of("bad")))
                .thenThrow(new IllegalArgumentException("unknown"))
                .thenThrow(new RuntimeException("db"));
        assertThat(controller.submit(request(FormType.W4, true, 7L)).getStatusCode().value()).isEqualTo(201);
        assertThat(controller.submit(request(FormType.W4, true, null)).getStatusCode().value()).isEqualTo(422);
        assertThat(controller.submit(request(FormType.W4, true, null)).getStatusCode().value()).isEqualTo(400);
        assertThat(controller.submit(request(FormType.W4, true, null)).getStatusCode().value()).isEqualTo(500);
    }

    @Test
    void mySubmissionsListsAndRejectsNonCaregivers() {
        when(submissionService.listForOwner(3L, UserFile.OwnerType.CAREGIVER)).thenReturn(List.of(
                FormSubmission.builder().id(1L).formType(FormType.I9).build()));
        assertThat(controller.mySubmissions().getStatusCode().value()).isEqualTo(200);

        caregiver.setRole(Role.PATIENT);
        assertThat(controller.mySubmissions().getStatusCode().value()).isEqualTo(403);
        assertThat(controller.submit(request(FormType.W4, true, null)).getStatusCode().value()).isEqualTo(403);
    }
}
