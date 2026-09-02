package com.careconnect.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.careconnect.model.PatientNote;

@Repository
public interface PatientNoteRepository extends JpaRepository<PatientNote, Long> {
    Optional<PatientNote> findById(Long id);

    Optional<List<PatientNote>> findByPatientId(Long patientId);

    void deleteById(Long id);
}



