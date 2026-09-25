package com.careconnect.service;

import com.careconnect.dto.SymptomDTO;
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
public class SymptomService {

    private final SymptomEntryRepository symptomRepo;
    private final PatientRepository patientRepo;

    @Transactional
    public SymptomDTO create(SymptomDTO dto) {
        Patient patient = patientRepo.findById(dto.patientId())
                .orElseThrow(() -> new IllegalArgumentException("Patient not found: " + dto.patientId()));

        SymptomEntry entry = SymptomEntry.builder()
                .patient(patient)
                .symptomKey(dto.symptomKey())
                .symptomValue(dto.symptomValue())
                .severity(dto.severity())
                .notes(dto.notes())
                .completed(dto.completed() != null ? dto.completed() : true)
                .takenAt(dto.takenAt() != null ? dto.takenAt() : Instant.now())
                .build();

        return toDto(symptomRepo.save(entry));
    }

    @Transactional
    public SymptomDTO update(Long id, SymptomDTO dto) {
        SymptomEntry e = symptomRepo.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Symptom not found: " + id));

        if (dto.symptomKey() != null) e.setSymptomKey(dto.symptomKey());
        if (dto.symptomValue() != null) e.setSymptomValue(dto.symptomValue());
        if (dto.severity() != null) e.setSeverity(dto.severity());
        if (dto.notes() != null) e.setNotes(dto.notes());
        if (dto.completed() != null) e.setCompleted(dto.completed());
        if (dto.takenAt() != null) e.setTakenAt(dto.takenAt());

        return toDto(symptomRepo.save(e));
    }

    public Optional<SymptomDTO> get(Long id) {
        return symptomRepo.findById(id).map(this::toDto);
    }

    public List<SymptomDTO> listByPatient(Long patientId) {
        return symptomRepo.findByPatientIdOrderByTakenAtDesc(patientId)
                .stream().map(this::toDto).toList();
    }

    @Transactional
    public void delete(Long id) {
        if (!symptomRepo.existsById(id)) {
            throw new IllegalArgumentException("Symptom not found: " + id);
        }
        symptomRepo.deleteById(id);
    }

    private SymptomDTO toDto(SymptomEntry e) {
        return SymptomDTO.builder()
                .id(e.getId())
                .patientId(e.getPatient().getId())
                .symptomKey(e.getSymptomKey())
                .symptomValue(e.getSymptomValue())
                .severity(e.getSeverity())
                .completed(e.getCompleted())
                .takenAt(e.getTakenAt())
                .notes(e.getNotes())
                .build();
    }
}
