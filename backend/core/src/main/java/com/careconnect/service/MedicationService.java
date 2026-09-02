package com.careconnect.service;

import com.careconnect.dto.MedicationDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.Medication;
import com.careconnect.model.Patient;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.PatientRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class MedicationService {

    private final MedicationRepository medicationRepository;
    private final PatientRepository patientRepository;
    private final NotificationService notificationService;
    private final CaregiverPatientLinkService caregiverPatientLinkService;

    // -------------------------------------------------------
    // Basic retrieval methods
    // -------------------------------------------------------

    /**
     * Get all active medications for a patient
     */
    public List<MedicationDTO> getActiveMedicationsForPatient(Long patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found with id: " + patientId));

        return medicationRepository.findByPatientAndIsActiveTrueOrderByCreatedAtDesc(patient)
                .stream()
                .map(this::mapToDTO)
                .toList();
    }

    /**
     * Get all medications (active/inactive)
     */
    public List<MedicationDTO> getAllMedicationsForPatient(Long patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found with id: " + patientId));

        return medicationRepository.findByPatientOrderByCreatedAtDesc(patient)
                .stream()
                .map(this::mapToDTO)
                .toList();
    }

    // -------------------------------------------------------
    // Create / Update / Approve / Delete
    // -------------------------------------------------------

    /**
     * Create a new medication (starts as PENDING)
     */
    @Transactional
    public MedicationDTO createMedication(MedicationDTO medicationDTO) {
        Patient patient = patientRepository.findById(medicationDTO.patientId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found with id: " + medicationDTO.patientId()));

        Medication medication = Medication.builder()
                .patient(patient)
                .medicationName(medicationDTO.medicationName())
                .dosage(medicationDTO.dosage())
                .frequency(medicationDTO.frequency())
                .route(medicationDTO.route())
                .medicationType(medicationDTO.medicationType())
                .prescribedBy(medicationDTO.prescribedBy())
                .prescribedDate(medicationDTO.prescribedDate())
                .startDate(medicationDTO.startDate())
                .endDate(medicationDTO.endDate())
                .notes(medicationDTO.notes())
                .lastTaken(medicationDTO.lastTaken())
                .isActive(medicationDTO.isActive() != null ? medicationDTO.isActive() : false)
                .approvalStatus("PENDING")
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();

        Medication saved = medicationRepository.save(medication);
        return mapToDTO(saved);
    }

    /**
     * Wrapper for adding medication by patientId (used by controller)
     */
    @Transactional
    public MedicationDTO addMedication(Long patientId, MedicationDTO medicationDTO) {
        // Ensure patient ID is set correctly before creation
        MedicationDTO dtoWithPatient = MedicationDTO.builder()
                .patientId(patientId)
                .medicationName(medicationDTO.medicationName())
                .dosage(medicationDTO.dosage())
                .frequency(medicationDTO.frequency())
                .route(medicationDTO.route())
                .medicationType(medicationDTO.medicationType())
                .prescribedBy(medicationDTO.prescribedBy())
                .prescribedDate(medicationDTO.prescribedDate())
                .startDate(medicationDTO.startDate())
                .endDate(medicationDTO.endDate())
                .notes(medicationDTO.notes())
                .lastTaken(medicationDTO.lastTaken())
                .isActive(false) // always start pending
                .build();

        return createMedication(dtoWithPatient);
    }

    /**
     * Update an existing medication
     */
    @Transactional
    public MedicationDTO updateMedication(Long id, MedicationDTO medicationDTO) {
        Medication existing = medicationRepository.findById(id)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Medication not found with id: " + id));

        if (medicationDTO.medicationName() != null) existing.setMedicationName(medicationDTO.medicationName());
        if (medicationDTO.dosage() != null) existing.setDosage(medicationDTO.dosage());
        if (medicationDTO.frequency() != null) existing.setFrequency(medicationDTO.frequency());
        if (medicationDTO.route() != null) existing.setRoute(medicationDTO.route());
        if (medicationDTO.medicationType() != null) existing.setMedicationType(medicationDTO.medicationType());
        if (medicationDTO.prescribedBy() != null) existing.setPrescribedBy(medicationDTO.prescribedBy());
        if (medicationDTO.prescribedDate() != null) existing.setPrescribedDate(medicationDTO.prescribedDate());
        if (medicationDTO.startDate() != null) existing.setStartDate(medicationDTO.startDate());
        if (medicationDTO.endDate() != null) existing.setEndDate(medicationDTO.endDate());
        if (medicationDTO.notes() != null) existing.setNotes(medicationDTO.notes());
        if (medicationDTO.isActive() != null) existing.setIsActive(medicationDTO.isActive());
        if (medicationDTO.lastTaken() != null) existing.setLastTaken(medicationDTO.lastTaken());

        existing.setUpdatedAt(Instant.now());
        Medication updated = medicationRepository.save(existing);
        return mapToDTO(updated);
    }

    /**
     * Approve medication
     */
    @Transactional
    public MedicationDTO approveMedication(Long patientId, Long medicationId) {
        Medication medication = medicationRepository.findById(medicationId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Medication not found with id: " + medicationId));

        if (!medication.getPatient().getId().equals(patientId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Medication does not belong to patient");
        }

        medication.setIsActive(true);
        medication.setApprovalStatus("APPROVED");
        medication.setUpdatedAt(Instant.now());
        Medication updated = medicationRepository.save(medication);

        // Optional: Send dummy approval notification
        notificationService.sendNotificationToUser(
                patientId,
                "Medication Approved",
                "Your medication '" + medication.getMedicationName() + "' was approved.",
                "MEDICATION_APPROVED",
                Map.of("medicationId", String.valueOf(medicationId))
        );

        return mapToDTO(updated);
    }

    /**
     * Soft delete (mark inactive and notify)
     */
    @Transactional
    public void deactivateMedication(Long patientId, Long medicationId) {
        Medication medication = medicationRepository.findById(medicationId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Medication not found with id: " + medicationId));

        if (!medication.getPatient().getId().equals(patientId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Medication does not belong to patient");
        }

        medication.setIsActive(false);
        medication.setApprovalStatus("REMOVAL_PENDING");
        medication.setUpdatedAt(Instant.now());
        medicationRepository.save(medication);

        // Dummy removal notification
        notificationService.sendNotificationToUser(
                patientId,
                "Medication Removal Requested",
                "Your medication '" + medication.getMedicationName() + "' has been marked for removal.",
                "MEDICATION_REMOVED",
                Map.of("medicationId", String.valueOf(medicationId))
        );
    }

    /**
     * Hard delete medication (Caregiver-side) - Actually removes from database
     */
    @Transactional
    public void hardDeleteMedication(Long patientId, Long medicationId, Long caregiverId) {
        Medication medication = medicationRepository.findById(medicationId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Medication not found with id: " + medicationId));

        if (!caregiverPatientLinkService.hasActiveLink(caregiverId, patientId)) {
            throw new AppException(HttpStatus.FORBIDDEN,
                    "Caregiver does not have active link to patient");
        }

        if (!medication.getPatient().getId().equals(patientId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Medication does not belong to patient");
        }

        // Optional: Verify caregiver has access to this patient
        // You can add caregiver-patient relationship validation here if needed

        // Hard delete from database
        medicationRepository.delete(medication);

        // Send notification to patient
        notificationService.sendNotificationToUser(
                patientId,
                "Medication Deleted",
                "Your medication '" + medication.getMedicationName() + "' has been removed by your caregiver.",
                "MEDICATION_DELETED",
                Map.of("medicationId", String.valueOf(medicationId), "caregiverId", String.valueOf(caregiverId))
        );
    }

    /**
     * Persist when a medication was taken for dose-window tracking.
     */
    @Transactional
    public MedicationDTO updateMedicationLastTaken(Long patientId, Long medicationId, Instant lastTaken) {
        Medication medication = medicationRepository.findById(medicationId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Medication not found with id: " + medicationId));

        if (!medication.getPatient().getId().equals(patientId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Medication does not belong to patient");
        }

        medication.setLastTaken(lastTaken);
        medication.setUpdatedAt(Instant.now());
        Medication updated = medicationRepository.save(medication);
        return mapToDTO(updated);
    }

    /**
     * Clear persisted taken state for a medication.
     */
    @Transactional
    public MedicationDTO clearMedicationLastTaken(Long patientId, Long medicationId) {
        return updateMedicationLastTaken(patientId, medicationId, null);
    }

    // -------------------------------------------------------
    // Query helpers
    // -------------------------------------------------------

    public Optional<MedicationDTO> getMedication(Long id) {
        return medicationRepository.findById(id).map(this::mapToDTO);
    }

    public List<MedicationDTO> getPendingMedications(Long patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found with id: " + patientId));

        return medicationRepository.findByPatientAndApprovalStatus(patient, "PENDING")
                .stream()
                .map(this::mapToDTO)
                .toList();
    }

    // -------------------------------------------------------
    // Mapper
    // -------------------------------------------------------

    private MedicationDTO mapToDTO(Medication medication) {
        return MedicationDTO.builder()
                .id(medication.getId())
                .patientId(medication.getPatient().getId())
                .medicationName(medication.getMedicationName())
                .dosage(medication.getDosage())
                .frequency(medication.getFrequency())
                .route(medication.getRoute())
                .medicationType(medication.getMedicationType())
                .prescribedBy(medication.getPrescribedBy())
                .prescribedDate(medication.getPrescribedDate())
                .startDate(medication.getStartDate())
                .endDate(medication.getEndDate())
                .notes(medication.getNotes())
                .isActive(medication.getIsActive())
                .lastTaken(medication.getLastTaken())
                .build();
    }
}
