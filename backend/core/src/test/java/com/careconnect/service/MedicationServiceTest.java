package com.careconnect.service;

import com.careconnect.dto.MedicationDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.Medication;
import com.careconnect.model.Medication.MedicationType;
import com.careconnect.model.Patient;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.PatientRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpStatus;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class MedicationServiceTest {

    @Mock
    private MedicationRepository medicationRepository;

    @Mock
    private PatientRepository patientRepository;

    @Mock
    private NotificationService notificationService;

    @InjectMocks
    private MedicationService medicationService;

    private Patient patient;
    private Medication medication;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        patient = Patient.builder()
                .id(1L)
                .firstName("John")
                .lastName("Doe")
                .build();

        medication = Medication.builder()
                .id(10L)
                .patient(patient)
                .medicationName("Aspirin")
                .dosage("100mg")
                .frequency("Once daily")
                .route("oral")
                .medicationType(MedicationType.PRESCRIPTION)
                .prescribedBy("Dr. Smith")
                .prescribedDate("2025-01-01")
                .startDate("2025-01-02")
                .endDate("2025-06-01")
                .notes("Take with food")
                .isActive(true)
                .approvalStatus("PENDING")
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();
    }

    // -------------------------------------------------------
    // getActiveMedicationsForPatient
    // -------------------------------------------------------

    @Test
    @DisplayName("getActiveMedicationsForPatient - patient exists with active medications - returns list of DTOs")
    void getActiveMedicationsForPatient_patientExistsWithActiveMeds_returnsDTOList() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.findByPatientAndIsActiveTrueOrderByCreatedAtDesc(patient))
                .thenReturn(List.of(medication));

        final List<MedicationDTO> result = medicationService.getActiveMedicationsForPatient(1L);

        assertEquals(1, result.size());
        assertEquals("Aspirin", result.get(0).medicationName());
        assertEquals(1L, result.get(0).patientId());
        assertEquals(10L, result.get(0).id());
        assertEquals("100mg", result.get(0).dosage());
        assertEquals("Once daily", result.get(0).frequency());
        assertEquals("oral", result.get(0).route());
        assertEquals(MedicationType.PRESCRIPTION, result.get(0).medicationType());
        assertEquals("Dr. Smith", result.get(0).prescribedBy());
        assertEquals("2025-01-01", result.get(0).prescribedDate());
        assertEquals("2025-01-02", result.get(0).startDate());
        assertEquals("2025-06-01", result.get(0).endDate());
        assertEquals("Take with food", result.get(0).notes());
        assertTrue(result.get(0).isActive());
        verify(patientRepository).findById(1L);
        verify(medicationRepository).findByPatientAndIsActiveTrueOrderByCreatedAtDesc(patient);
    }

    @Test
    @DisplayName("getActiveMedicationsForPatient - patient exists with no medications - returns empty list")
    void getActiveMedicationsForPatient_patientExistsNoMeds_returnsEmptyList() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.findByPatientAndIsActiveTrueOrderByCreatedAtDesc(patient))
                .thenReturn(List.of());

        final List<MedicationDTO> result = medicationService.getActiveMedicationsForPatient(1L);

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getActiveMedicationsForPatient - patient not found - throws AppException")
    void getActiveMedicationsForPatient_patientNotFound_throwsAppException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.getActiveMedicationsForPatient(99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Patient not found with id: 99", ex.getMessage());
    }

    // -------------------------------------------------------
    // getAllMedicationsForPatient
    // -------------------------------------------------------

    @Test
    @DisplayName("getAllMedicationsForPatient - patient exists with medications - returns list of DTOs")
    void getAllMedicationsForPatient_patientExistsWithMeds_returnsDTOList() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.findByPatientOrderByCreatedAtDesc(patient))
                .thenReturn(List.of(medication));

        final List<MedicationDTO> result = medicationService.getAllMedicationsForPatient(1L);

        assertEquals(1, result.size());
        assertEquals("Aspirin", result.get(0).medicationName());
    }

    @Test
    @DisplayName("getAllMedicationsForPatient - patient not found - throws AppException")
    void getAllMedicationsForPatient_patientNotFound_throwsAppException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.getAllMedicationsForPatient(99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Patient not found with id: 99", ex.getMessage());
    }

    // -------------------------------------------------------
    // createMedication
    // -------------------------------------------------------

    @Test
    @DisplayName("createMedication - valid DTO with isActive true - creates medication with given isActive")
    void createMedication_validDTOWithIsActiveTrue_createsMedication() throws Exception {
        final MedicationDTO dto = MedicationDTO.builder()
                .patientId(1L)
                .medicationName("Ibuprofen")
                .dosage("200mg")
                .frequency("Twice daily")
                .route("oral")
                .medicationType(MedicationType.OVER_THE_COUNTER)
                .prescribedBy("Dr. Jones")
                .prescribedDate("2025-02-01")
                .startDate("2025-02-02")
                .endDate("2025-08-01")
                .notes("After meals")
                .isActive(true)
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.save(any(Medication.class))).thenAnswer(invocation -> {
            final Medication saved = invocation.getArgument(0);
            saved.setId(20L);
            return saved;
        });

        final MedicationDTO result = medicationService.createMedication(dto);

        assertEquals("Ibuprofen", result.medicationName());
        assertEquals("200mg", result.dosage());
        assertEquals(1L, result.patientId());
        assertTrue(result.isActive());
        verify(medicationRepository).save(any(Medication.class));
    }

    @Test
    @DisplayName("createMedication - valid DTO with isActive null - defaults isActive to false")
    void createMedication_validDTOWithIsActiveNull_defaultsIsActiveToFalse() throws Exception {
        final MedicationDTO dto = MedicationDTO.builder()
                .patientId(1L)
                .medicationName("Vitamin D")
                .isActive(null)
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.save(any(Medication.class))).thenAnswer(invocation -> {
            final Medication saved = invocation.getArgument(0);
            saved.setId(30L);
            return saved;
        });

        final MedicationDTO result = medicationService.createMedication(dto);

        assertFalse(result.isActive());
    }

    @Test
    @DisplayName("createMedication - valid DTO with isActive false - sets isActive to false")
    void createMedication_validDTOWithIsActiveFalse_setsIsActiveToFalse() throws Exception {
        final MedicationDTO dto = MedicationDTO.builder()
                .patientId(1L)
                .medicationName("Vitamin C")
                .isActive(false)
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.save(any(Medication.class))).thenAnswer(invocation -> {
            final Medication saved = invocation.getArgument(0);
            saved.setId(31L);
            return saved;
        });

        final MedicationDTO result = medicationService.createMedication(dto);

        assertFalse(result.isActive());
    }

    @Test
    @DisplayName("createMedication - patient not found - throws AppException")
    void createMedication_patientNotFound_throwsAppException() throws Exception {
        final MedicationDTO dto = MedicationDTO.builder()
                .patientId(99L)
                .medicationName("Test")
                .build();

        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.createMedication(dto));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Patient not found with id: 99", ex.getMessage());
    }

    // -------------------------------------------------------
    // addMedication
    // -------------------------------------------------------

    @Test
    @DisplayName("addMedication - valid patientId and DTO - creates medication with correct patient and isActive false")
    void addMedication_validPatientIdAndDTO_createsMedicationWithIsActiveFalse() throws Exception {
        final MedicationDTO dto = MedicationDTO.builder()
                .medicationName("Metformin")
                .dosage("500mg")
                .frequency("Once daily")
                .route("oral")
                .medicationType(MedicationType.PRESCRIPTION)
                .prescribedBy("Dr. Lee")
                .prescribedDate("2025-03-01")
                .startDate("2025-03-02")
                .endDate("2025-09-01")
                .notes("With dinner")
                .isActive(true) // should be overridden to false
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.save(any(Medication.class))).thenAnswer(invocation -> {
            final Medication saved = invocation.getArgument(0);
            saved.setId(40L);
            return saved;
        });

        final MedicationDTO result = medicationService.addMedication(1L, dto);

        assertEquals("Metformin", result.medicationName());
        assertEquals(1L, result.patientId());
        assertFalse(result.isActive()); // always starts as pending/false
    }

    @Test
    @DisplayName("addMedication - patient not found - throws AppException")
    void addMedication_patientNotFound_throwsAppException() throws Exception {
        final MedicationDTO dto = MedicationDTO.builder()
                .medicationName("Test")
                .build();

        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.addMedication(99L, dto));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
    }

    // -------------------------------------------------------
    // updateMedication
    // -------------------------------------------------------

    @Test
    @DisplayName("updateMedication - all fields non-null - updates all fields")
    void updateMedication_allFieldsNonNull_updatesAllFields() throws Exception {
        final MedicationDTO updateDto = MedicationDTO.builder()
                .medicationName("Updated Name")
                .dosage("200mg")
                .frequency("Twice daily")
                .route("injection")
                .medicationType(MedicationType.EMERGENCY)
                .prescribedBy("Dr. New")
                .prescribedDate("2025-04-01")
                .startDate("2025-04-02")
                .endDate("2025-12-01")
                .notes("Updated notes")
                .isActive(false)
                .build();

        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));
        when(medicationRepository.save(any(Medication.class))).thenAnswer(invocation -> invocation.getArgument(0));

        final MedicationDTO result = medicationService.updateMedication(10L, updateDto);

        assertEquals("Updated Name", result.medicationName());
        assertEquals("200mg", result.dosage());
        assertEquals("Twice daily", result.frequency());
        assertEquals("injection", result.route());
        assertEquals(MedicationType.EMERGENCY, result.medicationType());
        assertEquals("Dr. New", result.prescribedBy());
        assertEquals("2025-04-01", result.prescribedDate());
        assertEquals("2025-04-02", result.startDate());
        assertEquals("2025-12-01", result.endDate());
        assertEquals("Updated notes", result.notes());
        assertFalse(result.isActive());
    }

    @Test
    @DisplayName("updateMedication - all fields null - no fields updated except updatedAt")
    void updateMedication_allFieldsNull_noFieldsUpdated() throws Exception {
        final MedicationDTO updateDto = MedicationDTO.builder()
                .medicationName(null)
                .dosage(null)
                .frequency(null)
                .route(null)
                .medicationType(null)
                .prescribedBy(null)
                .prescribedDate(null)
                .startDate(null)
                .endDate(null)
                .notes(null)
                .isActive(null)
                .build();

        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));
        when(medicationRepository.save(any(Medication.class))).thenAnswer(invocation -> invocation.getArgument(0));

        final MedicationDTO result = medicationService.updateMedication(10L, updateDto);

        // Original values should remain unchanged
        assertEquals("Aspirin", result.medicationName());
        assertEquals("100mg", result.dosage());
        assertEquals("Once daily", result.frequency());
        assertEquals("oral", result.route());
        assertEquals(MedicationType.PRESCRIPTION, result.medicationType());
        assertEquals("Dr. Smith", result.prescribedBy());
        assertEquals("2025-01-01", result.prescribedDate());
        assertEquals("2025-01-02", result.startDate());
        assertEquals("2025-06-01", result.endDate());
        assertEquals("Take with food", result.notes());
        assertTrue(result.isActive());
    }

    @Test
    @DisplayName("updateMedication - medication not found - throws AppException")
    void updateMedication_medicationNotFound_throwsAppException() throws Exception {
        final MedicationDTO updateDto = MedicationDTO.builder().medicationName("X").build();

        when(medicationRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.updateMedication(99L, updateDto));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Medication not found with id: 99", ex.getMessage());
    }

    // -------------------------------------------------------
    // approveMedication
    // -------------------------------------------------------

    @Test
    @DisplayName("approveMedication - valid patientId and medicationId - approves and notifies")
    void approveMedication_validIds_approvesAndNotifies() throws Exception {
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));
        when(medicationRepository.save(any(Medication.class))).thenAnswer(invocation -> invocation.getArgument(0));

        final MedicationDTO result = medicationService.approveMedication(1L, 10L);

        assertTrue(result.isActive());
        assertEquals("Aspirin", result.medicationName());
        verify(notificationService).sendNotificationToUser(
                eq(1L),
                eq("Medication Approved"),
                eq("Your medication 'Aspirin' was approved."),
                eq("MEDICATION_APPROVED"),
                eq(Map.of("medicationId", "10"))
        );
    }

    @Test
    @DisplayName("approveMedication - medication not found - throws AppException")
    void approveMedication_medicationNotFound_throwsAppException() throws Exception {
        when(medicationRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.approveMedication(1L, 99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Medication not found with id: 99", ex.getMessage());
    }

    @Test
    @DisplayName("approveMedication - medication does not belong to patient - throws FORBIDDEN")
    void approveMedication_medicationNotBelongingToPatient_throwsForbidden() throws Exception {
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.approveMedication(999L, 10L));

        assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
        assertEquals("Medication does not belong to patient", ex.getMessage());
    }

    // -------------------------------------------------------
    // deactivateMedication
    // -------------------------------------------------------

    @Test
    @DisplayName("deactivateMedication - valid patientId and medicationId - deactivates and notifies")
    void deactivateMedication_validIds_deactivatesAndNotifies() throws Exception {
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));

        medicationService.deactivateMedication(1L, 10L);

        assertFalse(medication.getIsActive());
        assertEquals("REMOVAL_PENDING", medication.getApprovalStatus());
        verify(medicationRepository).save(medication);
        verify(notificationService).sendNotificationToUser(
                eq(1L),
                eq("Medication Removal Requested"),
                eq("Your medication 'Aspirin' has been marked for removal."),
                eq("MEDICATION_REMOVED"),
                eq(Map.of("medicationId", "10"))
        );
    }

    @Test
    @DisplayName("deactivateMedication - medication not found - throws AppException")
    void deactivateMedication_medicationNotFound_throwsAppException() throws Exception {
        when(medicationRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.deactivateMedication(1L, 99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Medication not found with id: 99", ex.getMessage());
    }

    @Test
    @DisplayName("deactivateMedication - medication does not belong to patient - throws FORBIDDEN")
    void deactivateMedication_medicationNotBelongingToPatient_throwsForbidden() throws Exception {
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.deactivateMedication(999L, 10L));

        assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
        assertEquals("Medication does not belong to patient", ex.getMessage());
    }

    // -------------------------------------------------------
    // hardDeleteMedication
    // -------------------------------------------------------

    @Test
    @DisplayName("hardDeleteMedication - valid params - archives and notifies")
    void hardDeleteMedication_validParams_archivesAndNotifies() throws Exception {
        final Long caregiverId = 50L;
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));

        medicationService.hardDeleteMedication(1L, 10L, caregiverId);

        assertFalse(medication.getIsActive());
        assertEquals("REMOVED", medication.getApprovalStatus());
        assertNotNull(medication.getUpdatedAt());
        verify(medicationRepository).save(medication);
        verify(medicationRepository, never()).delete(medication);
        verify(notificationService).sendNotificationToUser(
                eq(1L),
                eq("Medication Deleted"),
                eq("Your medication 'Aspirin' has been removed by your caregiver."),
                eq("MEDICATION_DELETED"),
                eq(Map.of("medicationId", "10", "caregiverId", "50"))
        );
    }

    @Test
    @DisplayName("hardDeleteMedication - medication not found - throws AppException")
    void hardDeleteMedication_medicationNotFound_throwsAppException() throws Exception {
        when(medicationRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.hardDeleteMedication(1L, 99L, 50L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Medication not found with id: 99", ex.getMessage());
    }

    @Test
    @DisplayName("hardDeleteMedication - medication does not belong to patient - throws FORBIDDEN")
    void hardDeleteMedication_medicationNotBelongingToPatient_throwsForbidden() throws Exception {
        final Long caregiverId = 50L;
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.hardDeleteMedication(999L, 10L, caregiverId));

        assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
        assertEquals("Medication does not belong to patient", ex.getMessage());
    }

    // -------------------------------------------------------
    // getMedication
    // -------------------------------------------------------

    @Test
    @DisplayName("getMedication - medication exists - returns Optional with DTO")
    void getMedication_medicationExists_returnsOptionalWithDTO() throws Exception {
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));

        final Optional<MedicationDTO> result = medicationService.getMedication(10L);

        assertTrue(result.isPresent());
        assertEquals("Aspirin", result.get().medicationName());
        assertEquals(10L, result.get().id());
    }

    @Test
    @DisplayName("getMedication - medication does not exist - returns empty Optional")
    void getMedication_medicationDoesNotExist_returnsEmptyOptional() throws Exception {
        when(medicationRepository.findById(99L)).thenReturn(Optional.empty());

        final Optional<MedicationDTO> result = medicationService.getMedication(99L);

        assertFalse(result.isPresent());
    }

    // -------------------------------------------------------
    // getPendingMedications
    // -------------------------------------------------------

    @Test
    @DisplayName("getPendingMedications - patient exists with pending meds - returns list of DTOs")
    void getPendingMedications_patientExistsWithPendingMeds_returnsDTOList() throws Exception {
        medication.setApprovalStatus("PENDING");
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.findByPatientAndApprovalStatus(patient, "PENDING"))
                .thenReturn(List.of(medication));

        final List<MedicationDTO> result = medicationService.getPendingMedications(1L);

        assertEquals(1, result.size());
        assertEquals("Aspirin", result.get(0).medicationName());
    }

    @Test
    @DisplayName("getPendingMedications - patient exists with no pending meds - returns empty list")
    void getPendingMedications_patientExistsNoPendingMeds_returnsEmptyList() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(medicationRepository.findByPatientAndApprovalStatus(patient, "PENDING"))
                .thenReturn(List.of());

        final List<MedicationDTO> result = medicationService.getPendingMedications(1L);

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPendingMedications - patient not found - throws AppException")
    void getPendingMedications_patientNotFound_throwsAppException() throws Exception {
        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> medicationService.getPendingMedications(99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        assertEquals("Patient not found with id: 99", ex.getMessage());
    }
}
