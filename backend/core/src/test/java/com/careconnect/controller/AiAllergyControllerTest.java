package com.careconnect.controller;

import com.careconnect.dto.AiAllergyDTO;
import com.careconnect.model.Allergy;
import com.careconnect.model.User;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AiAllergyService;
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
class AiAllergyControllerTest {

    @Mock
    private AiAllergyService aiAllergyService;
    @Mock
    private AllergyRepository allergyRepository;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private AiAllergyController controller;

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

        final AiAllergyDTO.Request request = new AiAllergyDTO.Request();
        request.setPatientId(2L);
        request.setText("I'm allergic to peanuts");

        assertThatThrownBy(() -> controller.analyze(request))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("ADMIN, CAREGIVER, or PATIENT role");
    }

    @Test
    @DisplayName("Should call requirePatientAccess when patientId is not null")
    void analyze_withPatientId_checksAccess() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);

        final List<Allergy> allergies = List.of();
        when(allergyRepository.findActiveAllergiesByPatientId(2L)).thenReturn(allergies);

        final AiAllergyDTO.Result result = new AiAllergyDTO.Result();
        result.setAllergen("Peanuts");
        result.setReaction("Hives");
        result.setSeverity("SEVERE");
        when(aiAllergyService.analyze(any(), eq(allergies))).thenReturn(result);

        final AiAllergyDTO.Request request = new AiAllergyDTO.Request();
        request.setPatientId(2L);
        request.setText("I'm allergic to peanuts");

        final ResponseEntity<?> response = controller.analyze(request);

        verify(authorizationService).requirePatientAccess(adminUser, 2L);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    @DisplayName("Should skip requirePatientAccess when patientId is null")
    void analyze_withoutPatientId_skipsAccessCheck() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);

        final AiAllergyDTO.Result result = new AiAllergyDTO.Result();
        result.setAllergen("Dust");
        result.setReaction("Sneezing");
        result.setSeverity("MILD");
        when(aiAllergyService.analyze(any(), eq(List.of()))).thenReturn(result);

        final AiAllergyDTO.Request request = new AiAllergyDTO.Request();
        request.setPatientId(null);
        request.setText("I sneeze around dust");

        final ResponseEntity<?> response = controller.analyze(request);

        verify(authorizationService, never()).requirePatientAccess(any(), any());
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    @DisplayName("Should return OK with result data on success")
    @SuppressWarnings("unchecked")
    void analyze_success_returnsOkWithData() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);

        final List<Allergy> allergies = List.of();
        when(allergyRepository.findActiveAllergiesByPatientId(10L)).thenReturn(allergies);

        final AiAllergyDTO.Result result = new AiAllergyDTO.Result();
        result.setAllergen("Penicillin");
        result.setReaction("Rash");
        result.setSeverity("MODERATE");
        when(aiAllergyService.analyze(any(), eq(allergies))).thenReturn(result);

        final AiAllergyDTO.Request request = new AiAllergyDTO.Request();
        request.setPatientId(10L);
        request.setText("penicillin gives me a rash");

        final ResponseEntity<?> response = controller.analyze(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        final Map<String, Object> data = (Map<String, Object>) body.get("data");
        assertThat(data.get("allergen")).isEqualTo("Penicillin");
        assertThat(data.get("reaction")).isEqualTo("Rash");
        assertThat(data.get("severity")).isEqualTo("MODERATE");
    }

    @Test
    @DisplayName("Should return bad request when service throws exception")
    @SuppressWarnings("unchecked")
    void analyze_serviceError_returnsBadRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        when(aiAllergyService.analyze(any(), eq(List.of()))).thenThrow(new RuntimeException("AI failed"));

        final AiAllergyDTO.Request request = new AiAllergyDTO.Request();
        request.setPatientId(null);
        request.setText("test");

        final ResponseEntity<?> response = controller.analyze(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error")).isEqualTo("AI_ANALYZE_FAILED");
        assertThat(body.get("message")).isEqualTo("AI failed");
    }
}
