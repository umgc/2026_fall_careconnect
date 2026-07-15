package com.careconnect.repository;

import com.careconnect.model.UspsMailpiece;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface UspsMailpieceRepository extends JpaRepository<UspsMailpiece, Long> {

    Optional<UspsMailpiece> findByPatientIdAndSourceKey(Long patientId, String sourceKey);

    List<UspsMailpiece> findByPatientIdAndDigestDate(Long patientId, LocalDate digestDate);
}
