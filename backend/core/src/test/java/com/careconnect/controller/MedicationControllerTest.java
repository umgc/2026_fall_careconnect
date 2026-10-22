package com.careconnect.controller;

import com.careconnect.dto.MedicationDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.MedicationService;
import com.careconnect.service.PatientService;
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
import org.springframework.mock.web.MockMultipartFile;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Test IDs TC-MED-AUTHZ-001 to 015, Software Test Plan §3.20 (PR #325, WBS 6.2.57, issue #317).
 * <p>
 * The path carries the patient record id ({@code patient.id}); {@code requirePatientAccess} compares
 * user ids. The record id and the user id differ here on purpose, so a controller that passes the
 * record id to the access check fails these tests.
 */
@ExtendWith(MockitoExtension.class)
class MedicationControllerTest {

    private static final Long PATIENT_ID = 1L;
    private static final Long PATIENT_USER_ID = 100L;
    private static final Long MEDICATION_ID = 42L;
    private static final Long CAREGIVER_ID = 7L;
    /** The one refusal message, whatever the reason (DEF-MED-10). */
    private static final String ACCESS_REFUSED = "Not authorized to access this patient's medications";
    @Mock
    private MedicationService medicationService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @Mock
    private PatientService patientService;
    @InjectMocks
    private MedicationController controller;

    private final User currentUser = User.builder().id(500L).build();

    @BeforeEach
    void patientRecord() throws Exception {
        lenient().when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
        lenient().when(patientService.getPatientById(PATIENT_ID))
                .thenReturn(patient(User.builder().id(PATIENT_USER_ID).build()));
    }

    private static Patient patient(final User user) {
        final Patient patient = new Patient();
        patient.setId(PATIENT_ID);
        patient.setUser(user);
        return patient;
    }

    private MedicationDTO dto(String name) {
        final MedicationDTO d = new MedicationDTO(null, null, name, null, null, null, null, null, null, null, null, null, null, null);
        return d;
    }

    private void verifyAccessCheckedWithPatientUserId() throws Exception {
        verify(authorizationService).requirePatientAccess(currentUser, PATIENT_USER_ID);
    }

    @FunctionalInterface
    private interface Endpoint {
        Object call() throws Exception;
    }

    /** All eight endpoints, each called for {@link #PATIENT_ID}. */
    private List<Endpoint> allEndpoints() {
        final MockMultipartFile empty = new MockMultipartFile("image", "label.jpg", "image/jpeg", new byte[0]);
        return List.of(
                () -> controller.getAllMedications(PATIENT_ID),
                () -> controller.getActiveMedications(PATIENT_ID),
                () -> controller.getPendingMedications(PATIENT_ID),
                () -> controller.addMedication(PATIENT_ID, dto("New-Med")),
                () -> controller.extractMedicationPhoto(PATIENT_ID, empty),
                () -> controller.approveMedication(PATIENT_ID, MEDICATION_ID),
                () -> controller.deleteMedication(PATIENT_ID, MEDICATION_ID),
                () -> controller.deleteMedicationByCaregiver(PATIENT_ID, MEDICATION_ID, CAREGIVER_ID));
    }

    //  getAllMedications

    @Test
    @DisplayName("TC-MED-AUTHZ-001: GET all medications returns the service list, access checked with the patient's user id")
    void getAllMedications_returnsListFromService() throws Exception {
        final List<MedicationDTO> meds = List.of(dto("Med-A"), dto("Med-B"));
        when(medicationService.getAllMedicationsForPatient(PATIENT_ID)).thenReturn(meds);

        final ResponseEntity<List<MedicationDTO>> response = controller.getAllMedications(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(meds);
        verifyAccessCheckedWithPatientUserId();
    }

    @Test
    @DisplayName("TC-MED-AUTHZ-002: GET all medications with none returns 200 and an empty list")
    void getAllMedications_emptyList_returnsOkWithEmptyBody() throws Exception {
        when(medicationService.getAllMedicationsForPatient(PATIENT_ID)).thenReturn(List.of());

        final ResponseEntity<List<MedicationDTO>> response = controller.getAllMedications(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
        verifyAccessCheckedWithPatientUserId();
    }

    //  getActiveMedications

    @Test
    @DisplayName("TC-MED-AUTHZ-003: GET active medications returns the service list, access checked with the patient's user id")
    void getActiveMedications_returnsActiveList() throws Exception {
        final List<MedicationDTO> active = List.of(dto("Active-Med"));
        when(medicationService.getActiveMedicationsForPatient(PATIENT_ID)).thenReturn(active);

        final ResponseEntity<List<MedicationDTO>> response = controller.getActiveMedications(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(active);
        verifyAccessCheckedWithPatientUserId();
    }

    @Test
    @DisplayName("TC-MED-AUTHZ-004: GET active medications with none returns 200 and an empty list")
    void getActiveMedications_emptyList_returnsOk() throws Exception {
        when(medicationService.getActiveMedicationsForPatient(PATIENT_ID)).thenReturn(List.of());

        final ResponseEntity<List<MedicationDTO>> response = controller.getActiveMedications(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
        verifyAccessCheckedWithPatientUserId();
    }

    //  getPendingMedications

    @Test
    @DisplayName("TC-MED-AUTHZ-005: GET pending medications returns the service list, access checked with the patient's user id")
    void getPendingMedications_returnsPendingList() throws Exception {
        final List<MedicationDTO> pending = List.of(dto("Pending-Med"));
        when(medicationService.getPendingMedications(PATIENT_ID)).thenReturn(pending);

        final ResponseEntity<List<MedicationDTO>> response = controller.getPendingMedications(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(pending);
        verifyAccessCheckedWithPatientUserId();
    }

    @Test
    @DisplayName("TC-MED-AUTHZ-006: GET pending medications with none returns 200 and an empty list")
    void getPendingMedications_emptyList_returnsOk() throws Exception {
        when(medicationService.getPendingMedications(PATIENT_ID)).thenReturn(List.of());

        final ResponseEntity<List<MedicationDTO>> response = controller.getPendingMedications(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
        verifyAccessCheckedWithPatientUserId();
    }

    //  addMedication

    @Test
    @DisplayName("TC-MED-AUTHZ-007: POST add medication delegates with the record id, access checked with the patient's user id")
    void addMedication_delegatesToServiceAndReturnsCreated() throws Exception {
        final MedicationDTO input = dto("New-Med");
        final MedicationDTO created = dto("New-Med");
        when(medicationService.addMedication(PATIENT_ID, input)).thenReturn(created);

        final ResponseEntity<MedicationDTO> response = controller.addMedication(PATIENT_ID, input);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(created);
        verify(medicationService).addMedication(PATIENT_ID, input);
        verifyAccessCheckedWithPatientUserId();
    }

    //  approveMedication

    @Test
    @DisplayName("TC-MED-AUTHZ-008: approve returns the message and approved medication, access checked with the patient's user id")
    void approveMedication_returnsOkWithMessageAndApprovedDto() throws Exception {
        final MedicationDTO approved = dto("Approved-Med");
        when(medicationService.approveMedication(PATIENT_ID, MEDICATION_ID)).thenReturn(approved);

        final ResponseEntity<?> response = controller.approveMedication(PATIENT_ID, MEDICATION_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.get("message")).isEqualTo("Medication approved successfully");
        assertThat(body.get("approvedMedication")).isEqualTo(approved);
        verify(medicationService).approveMedication(PATIENT_ID, MEDICATION_ID);
        verifyAccessCheckedWithPatientUserId();
    }

    //  deleteMedication

    @Test
    @DisplayName("TC-MED-AUTHZ-009: delete deactivates and returns the message, access checked with the patient's user id")
    void deleteMedication_deactivatesAndReturnsMessage() throws Exception {
        doNothing().when(medicationService).deactivateMedication(PATIENT_ID, MEDICATION_ID);

        final ResponseEntity<?> response = controller.deleteMedication(PATIENT_ID, MEDICATION_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.get("message")).isEqualTo("Medication removed and notification sent");
        verify(medicationService).deactivateMedication(PATIENT_ID, MEDICATION_ID);
        verifyAccessCheckedWithPatientUserId();
    }

    //  deleteMedicationByCaregiver

    @Test
    @DisplayName("TC-MED-AUTHZ-010: caregiver hard delete returns the message, access checked with the patient's user id")
    void deleteMedicationByCaregiver_hardDeletesAndReturnsMessage() throws Exception {
        doNothing().when(medicationService).hardDeleteMedication(PATIENT_ID, MEDICATION_ID, CAREGIVER_ID);

        final ResponseEntity<?> response = controller.deleteMedicationByCaregiver(PATIENT_ID, MEDICATION_ID, CAREGIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.get("message")).isEqualTo("Medication deleted successfully");
        verify(medicationService).hardDeleteMedication(PATIENT_ID, MEDICATION_ID, CAREGIVER_ID);
        verifyAccessCheckedWithPatientUserId();
    }

    //  access check across all eight endpoints

    @Test
    @DisplayName("TC-MED-AUTHZ-011: all 8 endpoints check access with the patient's user id and never with the record id")
    void everyEndpointPassesPatientUserId() throws Exception {
        when(medicationService.approveMedication(PATIENT_ID, MEDICATION_ID)).thenReturn(dto("Approved-Med"));

        for (final Endpoint endpoint : allEndpoints()) {
            endpoint.call();
        }

        verify(authorizationService, times(8)).requirePatientAccess(currentUser, PATIENT_USER_ID);
        verify(authorizationService, never()).requirePatientAccess(any(), eq(PATIENT_ID));
    }

    @Test
    @DisplayName("TC-MED-AUTHZ-012: a patient record that does not exist is refused like no access, on all 8 endpoints, and no medication is read or written")
    void unknownPatientRecordIsRefusedLikeNoAccess() throws Exception {
        when(patientService.getPatientById(PATIENT_ID))
                .thenThrow(new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        for (final Endpoint endpoint : allEndpoints()) {
            assertThatThrownBy(endpoint::call)
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessage(ACCESS_REFUSED);
        }

        verify(authorizationService, never()).requirePatientAccess(any(), any());
        verifyNoInteractions(medicationService);
    }

    @Test
    @DisplayName("TC-MED-AUTHZ-013: a patient record with no user is refused, not a 500 from a NullPointerException, on all 8 endpoints")
    void patientRecordWithoutUserIsRefused() throws Exception {
        when(patientService.getPatientById(PATIENT_ID)).thenReturn(patient(null));

        for (final Endpoint endpoint : allEndpoints()) {
            assertThatThrownBy(endpoint::call)
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessage(ACCESS_REFUSED);
        }

        verify(authorizationService, never()).requirePatientAccess(any(), any());
        verifyNoInteractions(medicationService);
    }

    @Test
    @DisplayName("TC-MED-AUTHZ-014: a refused caller gets one message on every endpoint, naming no patient id, and no medication is read or written")
    void refusalCarriesOneMessageAndTouchesNoMedication() throws Exception {
        doThrow(new UnauthorizedException("Caregiver 'c@example.test' is not assigned to patient 100"))
                .when(authorizationService).requirePatientAccess(currentUser, PATIENT_USER_ID);

        for (final Endpoint endpoint : allEndpoints()) {
            assertThatThrownBy(endpoint::call)
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessage(ACCESS_REFUSED)
                    .hasMessageNotContaining(String.valueOf(PATIENT_USER_ID));
        }

        verifyNoInteractions(medicationService);
    }

    @Test
    @DisplayName("TC-MED-AUTHZ-015: a patient lookup failure other than not-found propagates unchanged and no medication is read")
    void otherLookupFailurePropagates() throws Exception {
        final AppException failure = new AppException(HttpStatus.SERVICE_UNAVAILABLE, "database unavailable");
        when(patientService.getPatientById(PATIENT_ID)).thenThrow(failure);

        assertThatThrownBy(() -> controller.getAllMedications(PATIENT_ID)).isSameAs(failure);

        verify(authorizationService, never()).requirePatientAccess(any(), any());
        verifyNoInteractions(medicationService);
    }
}
