package com.careconnect.controller;

import com.careconnect.dto.SymptomEntryDTO;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.SymptomEntryService;
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

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SymptomEntryControllerTest {

    @Mock
    private SymptomEntryService symptomEntryService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private SymptomEntryController controller;

    private User adminUser;
    private SymptomEntryDTO sampleDto;

    @BeforeEach
    void setUp() {
        adminUser = User.builder().id(1L).email("admin@test.com").role(Role.ADMIN).build();
        sampleDto = SymptomEntryDTO.builder()
                .id(1L)
                .patientId(10L)
                .symptomKey("headache")
                .symptomValue("throbbing")
                .severity(3)
                .completed(true)
                .takenAt(Instant.now())
                .build();
    }

    // ─── createSymptom ────────────────────────────────────────────────────────

    @Test
    @DisplayName("Should return CREATED on successful symptom creation")
    @SuppressWarnings("unchecked")
    void createSymptom_success_returnsCreated() {
        when(symptomEntryService.createSymptom(any())).thenReturn(sampleDto);

        final ResponseEntity<?> response = controller.createSymptom(sampleDto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("message")).isEqualTo("Symptom created successfully");
        assertThat(body.get("data")).isEqualTo(sampleDto);
    }

    @Test
    @DisplayName("Should return BAD_REQUEST on IllegalArgumentException")
    @SuppressWarnings("unchecked")
    void createSymptom_illegalArg_returnsBadRequest() {
        when(symptomEntryService.createSymptom(any()))
                .thenThrow(new IllegalArgumentException("Patient not found with id: 99"));

        final ResponseEntity<?> response = controller.createSymptom(sampleDto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error")).isEqualTo("Patient not found with id: 99");
    }

    @Test
    @DisplayName("Should return INTERNAL_SERVER_ERROR on unexpected exception")
    @SuppressWarnings("unchecked")
    void createSymptom_unexpectedError_returnsInternalError() {
        when(symptomEntryService.createSymptom(any()))
                .thenThrow(new RuntimeException("DB error"));

        final ResponseEntity<?> response = controller.createSymptom(sampleDto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error")).isEqualTo("Failed to create symptom");
    }

    // ─── getSymptoms ──────────────────────────────────────────────────────────

    @Test
    @DisplayName("Should return OK with symptoms list on success")
    @SuppressWarnings("unchecked")
    void getSymptoms_success_returnsOk() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(symptomEntryService.getSymptomsForPatient(10L)).thenReturn(List.of(sampleDto));

        final ResponseEntity<?> response = controller.getSymptoms(10L);

        verify(authorizationService).requirePatientAccess(adminUser, 10L);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("message")).isEqualTo("Symptoms retrieved successfully");
        assertThat((List<?>) body.get("data")).hasSize(1);
    }

    @Test
    @DisplayName("Should propagate UnauthorizedException from requirePatientAccess")
    void getSymptoms_unauthorized_throwsException() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        doThrow(new UnauthorizedException("Access denied"))
                .when(authorizationService).requirePatientAccess(adminUser, 10L);

        assertThatThrownBy(() -> controller.getSymptoms(10L))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Access denied");
    }

    @Test
    @DisplayName("Should return INTERNAL_SERVER_ERROR when service fails")
    @SuppressWarnings("unchecked")
    void getSymptoms_serviceError_returnsInternalError() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(symptomEntryService.getSymptomsForPatient(10L))
                .thenThrow(new RuntimeException("DB error"));

        final ResponseEntity<?> response = controller.getSymptoms(10L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error")).isEqualTo("Failed to fetch symptoms");
    }

    // ─── deleteSymptom ────────────────────────────────────────────────────────

    @Test
    @DisplayName("Should return OK on successful deletion")
    @SuppressWarnings("unchecked")
    void deleteSymptom_success_returnsOk() {
        doNothing().when(symptomEntryService).deleteSymptom(1L);

        final ResponseEntity<?> response = controller.deleteSymptom(1L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("message")).isEqualTo("Symptom deleted successfully");
    }

    @Test
    @DisplayName("Should return BAD_REQUEST on IllegalArgumentException during delete")
    @SuppressWarnings("unchecked")
    void deleteSymptom_notFound_returnsBadRequest() {
        doThrow(new IllegalArgumentException("Symptom not found with id: 99"))
                .when(symptomEntryService).deleteSymptom(99L);

        final ResponseEntity<?> response = controller.deleteSymptom(99L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error")).isEqualTo("Symptom not found with id: 99");
    }

    @Test
    @DisplayName("Should return INTERNAL_SERVER_ERROR on unexpected exception during delete")
    @SuppressWarnings("unchecked")
    void deleteSymptom_unexpectedError_returnsInternalError() {
        doThrow(new RuntimeException("DB error"))
                .when(symptomEntryService).deleteSymptom(1L);

        final ResponseEntity<?> response = controller.deleteSymptom(1L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error")).isEqualTo("Failed to delete symptom");
    }
}
