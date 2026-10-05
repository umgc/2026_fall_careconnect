package com.careconnect.controller;

import com.careconnect.dto.AiSymptomDTO;
import com.careconnect.model.SymptomEntry;
import com.careconnect.model.User;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.repository.SymptomEntryRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AiSymptomService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AiSymptomControllerTest {

    @Mock
    private AiSymptomService aiSymptomService;
    @Mock
    private AllergyRepository allergyRepository;
    @Mock
    private SymptomEntryRepository symptomEntryRepository;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private AiSymptomController controller;

    private User adminUser;
    private User patientUser;
    private User familyUser;

    @BeforeEach
    void setUp() {
        adminUser = User.builder().id(1L).email("admin@test.com").role(Role.ADMIN).build();
        patientUser = User.builder().id(2L).email("patient@test.com").role(Role.PATIENT).build();
        familyUser = User.builder().id(3L).email("family@test.com").role(Role.FAMILY_MEMBER).build();
    }

    @Test
    @DisplayName("Should throw UnauthorizedException when user is family member")
    void analyze_familyMember_throwsUnauthorized() {
        when(securityUtil.resolveCurrentUser()).thenReturn(familyUser);

        final AiSymptomDTO.Request request = new AiSymptomDTO.Request();
        request.setPatientId(2L);
        request.setText("I have a headache");

        assertThatThrownBy(() -> controller.analyze(request))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("ADMIN, CAREGIVER, or PATIENT role");
    }

    @Test
    @DisplayName("Should call requirePatientAccess when patientId is not null")
    void analyze_withPatientId_checksAccess() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(allergyRepository.findActiveAllergiesByPatientId(2L)).thenReturn(List.of());
        when(symptomEntryRepository.findByPatientIdOrderByTakenAtDesc(2L)).thenReturn(List.of());

        final AiSymptomDTO.Result result = new AiSymptomDTO.Result();
        result.setSymptomKey("headache");
        result.setSymptomValue("throbbing");
        result.setSeverity("MODERATE");
        result.setNotes("test");
        when(aiSymptomService.analyze(any(), any(), any())).thenReturn(result);

        final AiSymptomDTO.Request request = new AiSymptomDTO.Request();
        request.setPatientId(2L);
        request.setText("I have a headache");

        final ResponseEntity<?> response = controller.analyze(request);

        verify(authorizationService).requirePatientAccess(adminUser, 2L);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    @DisplayName("Should skip requirePatientAccess when patientId is null")
    void analyze_withoutPatientId_skipsAccessCheck() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);

        final AiSymptomDTO.Result result = new AiSymptomDTO.Result();
        result.setSymptomKey("anxiety");
        result.setSymptomValue("racing heart");
        result.setSeverity("MILD");
        result.setNotes("test");
        when(aiSymptomService.analyze(any(), eq(List.of()), eq(List.of()))).thenReturn(result);

        final AiSymptomDTO.Request request = new AiSymptomDTO.Request();
        request.setPatientId(null);
        request.setText("I feel anxious");

        final ResponseEntity<?> response = controller.analyze(request);

        verify(authorizationService, never()).requirePatientAccess(any(), any());
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    @DisplayName("Should return OK with result data on success")
    @SuppressWarnings("unchecked")
    void analyze_success_returnsOkWithData() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(allergyRepository.findActiveAllergiesByPatientId(10L)).thenReturn(List.of());
        when(symptomEntryRepository.findByPatientIdOrderByTakenAtDesc(10L)).thenReturn(List.of());

        final AiSymptomDTO.Result result = new AiSymptomDTO.Result();
        result.setSymptomKey("headache");
        result.setSymptomValue("throbbing pain");
        result.setSeverity("SEVERE");
        result.setNotes("migraine");
        when(aiSymptomService.analyze(any(), any(), any())).thenReturn(result);

        final AiSymptomDTO.Request request = new AiSymptomDTO.Request();
        request.setPatientId(10L);
        request.setText("severe headache");

        final ResponseEntity<?> response = controller.analyze(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        final Map<String, Object> data = (Map<String, Object>) body.get("data");
        assertThat(data.get("symptomKey")).isEqualTo("headache");
        assertThat(data.get("symptomValue")).isEqualTo("throbbing pain");
        assertThat(data.get("severity")).isEqualTo("SEVERE");
        assertThat(data.get("notes")).isEqualTo("migraine");
    }

    @Test
    @DisplayName("Should limit recent symptoms to 5")
    void analyze_withPatientId_limitsRecentSymptoms() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(allergyRepository.findActiveAllergiesByPatientId(5L)).thenReturn(List.of());

        // Return 7 entries to verify limit(5) is applied
        final List<SymptomEntry> sevenEntries = List.of(
                mock(SymptomEntry.class), mock(SymptomEntry.class), mock(SymptomEntry.class),
                mock(SymptomEntry.class), mock(SymptomEntry.class), mock(SymptomEntry.class),
                mock(SymptomEntry.class)
        );
        when(symptomEntryRepository.findByPatientIdOrderByTakenAtDesc(5L)).thenReturn(sevenEntries);

        final AiSymptomDTO.Result result = new AiSymptomDTO.Result();
        result.setSymptomKey("test");
        result.setSymptomValue("test");
        result.setSeverity("MILD");
        result.setNotes("test");
        when(aiSymptomService.analyze(any(), any(), any())).thenReturn(result);

        final AiSymptomDTO.Request request = new AiSymptomDTO.Request();
        request.setPatientId(5L);
        request.setText("test");

        controller.analyze(request);

        // Verify the service was called (the limit(5) happens in the stream)
        verify(aiSymptomService).analyze(any(), any(), argThat(list -> list.size() == 5));
    }

    @Test
    @DisplayName("Should return bad request when service throws exception")
    @SuppressWarnings("unchecked")
    void analyze_serviceError_returnsBadRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(aiSymptomService.analyze(any(), eq(List.of()), eq(List.of())))
                .thenThrow(new RuntimeException("AI failed"));

        final AiSymptomDTO.Request request = new AiSymptomDTO.Request();
        request.setPatientId(null);
        request.setText("test");

        final ResponseEntity<?> response = controller.analyze(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error")).isEqualTo("AI_ANALYZE_FAILED");
        assertThat(body.get("message")).isEqualTo("AI failed");
    }
}
