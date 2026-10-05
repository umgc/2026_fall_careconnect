package com.careconnect.service;

import com.careconnect.dto.AllergyDTO;
import com.careconnect.model.Allergy;
import com.careconnect.model.Patient;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.repository.PatientRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class AllergyService {

    private final AllergyRepository allergyRepository;
    private final PatientRepository patientRepository;

    /**
     * Create a new allergy for a patient
     */
    @Transactional
    public AllergyDTO createAllergy(AllergyDTO dto) {
        Patient patient = patientRepository.findById(dto.patientId())
                .orElseThrow(() -> new IllegalArgumentException("Patient not found with id: " + dto.patientId()));

        // Check if allergy already exists for this patient
        if (allergyRepository.existsByPatientAndAllergenIgnoreCaseAndIsActiveTrue(patient, dto.allergen())) {
            throw new IllegalArgumentException("Active allergy for '" + dto.allergen() + "' already exists for this patient");
        }

        Allergy allergy = Allergy.builder()
                .patient(patient)
                .allergen(dto.allergen())
                .allergyType(dto.allergyType())
                .severity(dto.severity())
                .reaction(dto.reaction())
                .notes(dto.notes())
                .diagnosedDate(dto.diagnosedDate())
                .isActive(dto.isActive() != null ? dto.isActive() : true)
                .build();

        Allergy saved = allergyRepository.save(allergy);
        return mapToDTO(saved);
    }

    /**
     * Update an existing allergy
     */
    @Transactional
    public AllergyDTO updateAllergy(Long id, AllergyDTO dto) {
        Allergy existing = allergyRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Allergy not found with id: " + id));

        // Update only non-null fields
        if (dto.allergen() != null) {
            existing.setAllergen(dto.allergen());
        }
        if (dto.allergyType() != null) {
            existing.setAllergyType(dto.allergyType());
        }
        if (dto.severity() != null) {
            existing.setSeverity(dto.severity());
        }
        if (dto.reaction() != null) {
            existing.setReaction(dto.reaction());
        }
        if (dto.notes() != null) {
            existing.setNotes(dto.notes());
        }
        if (dto.diagnosedDate() != null) {
            existing.setDiagnosedDate(dto.diagnosedDate());
        }
        if (dto.isActive() != null) {
            existing.setIsActive(dto.isActive());
        }

        Allergy updated = allergyRepository.save(existing);
        return mapToDTO(updated);
    }

    /**
     * Get all allergies for a patient
     */
    public List<AllergyDTO> getAllergiesForPatient(Long patientId) {
        return allergyRepository.findByPatientId(patientId)
                .stream()
                .map(this::mapToDTO)
                .toList();
    }

    /**
     * Get active allergies for a patient
     */
    public List<AllergyDTO> getActiveAllergiesForPatient(Long patientId) {
        return allergyRepository.findActiveAllergiesByPatientId(patientId)
                .stream()
                .map(this::mapToDTO)
                .toList();
    }

    /**
     * Get a specific allergy by ID
     */
    public Optional<AllergyDTO> getAllergy(Long id) {
        return allergyRepository.findById(id)
                .map(this::mapToDTO);
    }

    /**
     * Deactivate an allergy (soft delete)
     */
    @Transactional
    public void deactivateAllergy(Long id) {
        Allergy allergy = allergyRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Allergy not found with id: " + id));

        allergy.setIsActive(false);
        allergyRepository.save(allergy);
    }

    /**
     * Permanently delete an allergy
     */
    @Transactional
    public void deleteAllergy(Long id) {
        if (!allergyRepository.existsById(id)) {
            throw new IllegalArgumentException("Allergy not found with id: " + id);
        }
        allergyRepository.deleteById(id);
    }

    /**
     * Map Allergy entity to DTO
     */
    private AllergyDTO mapToDTO(Allergy allergy) {
        return AllergyDTO.builder()
                .id(allergy.getId())
                .patientId(allergy.getPatient().getId())
                .allergen(allergy.getAllergen())
                .allergyType(allergy.getAllergyType())
                .severity(allergy.getSeverity())
                .reaction(allergy.getReaction())
                .notes(allergy.getNotes())
                .diagnosedDate(allergy.getDiagnosedDate())
                .isActive(allergy.getIsActive())
                .build();
    }
}
