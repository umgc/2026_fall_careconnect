package com.careconnect.service;

import com.careconnect.dto.SymptomEntryDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.SymptomEntry;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.SymptomEntryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class SymptomEntryService {

    private final SymptomEntryRepository symptomEntryRepository;
    private final PatientRepository patientRepository;

    /**
     * Create a new symptom entry for a patient
     */
    @Transactional
    public SymptomEntryDTO createSymptom(SymptomEntryDTO dto) {
        Patient patient = patientRepository.findById(dto.patientId())
                .orElseThrow(() -> new IllegalArgumentException("Patient not found with id: " + dto.patientId()));

        SymptomEntry entry = SymptomEntry.builder()
                .patient(patient)
                .caregiver(null)
                .symptomKey(dto.symptomKey())
                .symptomValue(dto.symptomValue())
                .severity(dto.severity())
                .takenAt(dto.takenAt() != null ? dto.takenAt() : Instant.now())
                .completed(true)
                .build();

        SymptomEntry saved = symptomEntryRepository.save(entry);
        return mapToDTO(saved);
    }

    /**
     * Get all symptom entries for a patient
     */
    public List<SymptomEntryDTO> getSymptomsForPatient(Long patientId) {
        return symptomEntryRepository.findAll().stream()
                .filter(e -> e.getPatient().getId().equals(patientId))
                .map(this::mapToDTO)
                .toList();
    }

    /**
     * Delete a symptom entry
     */
    @Transactional
    public void deleteSymptom(Long id) {
        if (!symptomEntryRepository.existsById(id)) {
            throw new IllegalArgumentException("Symptom not found with id: " + id);
        }
        symptomEntryRepository.deleteById(id);
    }

    private SymptomEntryDTO mapToDTO(SymptomEntry entry) {
        return SymptomEntryDTO.builder()
                .id(entry.getId())
                .patientId(entry.getPatient().getId())
                .symptomKey(entry.getSymptomKey())
                .symptomValue(entry.getSymptomValue())
                .severity(entry.getSeverity())
                .takenAt(entry.getTakenAt())
                .completed(entry.getCompleted())
                .build();
    }
}
