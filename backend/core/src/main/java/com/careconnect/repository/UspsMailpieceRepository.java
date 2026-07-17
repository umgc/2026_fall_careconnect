package com.careconnect.repository;

import com.careconnect.model.UspsMailpiece;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

@Repository
public interface UspsMailpieceRepository extends JpaRepository<UspsMailpiece, Long> {

    Optional<UspsMailpiece> findByPatientIdAndSourceKey(Long patientId, String sourceKey);

    List<UspsMailpiece> findByPatientIdAndDigestDate(Long patientId, LocalDate digestDate);

    List<UspsMailpiece> findByPatientIdAndIdIn(Long patientId, Collection<Long> ids);

    /**
     * Keyword / natural-language token match over durable mailpiece fields
     * (Task 3.14.7). Case-insensitive substring match on sender, summary,
     * OCR text, importance category, and recorded reasoning.
     */
    @Query("""
            SELECT m FROM UspsMailpiece m
            WHERE m.patientId = :patientId
              AND (
                   LOWER(COALESCE(m.sender, '')) LIKE LOWER(CONCAT('%', :term, '%'))
                OR LOWER(COALESCE(m.summary, '')) LIKE LOWER(CONCAT('%', :term, '%'))
                OR LOWER(COALESCE(m.ocrText, '')) LIKE LOWER(CONCAT('%', :term, '%'))
                OR LOWER(COALESCE(m.importanceCategory, '')) LIKE LOWER(CONCAT('%', :term, '%'))
                OR LOWER(COALESCE(m.importanceReasoning, '')) LIKE LOWER(CONCAT('%', :term, '%'))
                OR LOWER(COALESCE(m.importanceLevel, '')) LIKE LOWER(CONCAT('%', :term, '%'))
                OR LOWER(COALESCE(m.externalId, '')) LIKE LOWER(CONCAT('%', :term, '%'))
              )
            """)
    List<UspsMailpiece> searchByPatientIdAndTerm(
            @Param("patientId") Long patientId,
            @Param("term") String term);
}
