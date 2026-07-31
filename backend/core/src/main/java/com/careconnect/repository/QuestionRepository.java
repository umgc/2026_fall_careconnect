package com.careconnect.repository;

import com.careconnect.model.Question;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface QuestionRepository extends JpaRepository<Question, Long> {

    // Return all active/inactive questions
    List<Question> findByActive(Boolean active);
    List<Question> findAllByActiveTrueAndFormKeyAndFormVersionOrderByOrdinalAsc(String formKey, int formVersion);

    // (Optional niceties)
    List<Question> findAllByActiveTrue();
    List<Question> findAllByActiveFalse();

    List<Question> findAllByOrderByOrdinalAsc();

    List<Question> findAllByActiveFalseOrderByOrdinalAsc();

    /** Shift ordinals within the same form/version at or above the given ordinal by 1. */
    @Modifying
    @Query("""
            UPDATE Question q
            SET q.ordinal = q.ordinal + 1
            WHERE q.ordinal >= :fromOrdinal
              AND q.id <> :excludeId
              AND q.formKey = :formKey
              AND q.formVersion = :formVersion
            """)
    void shiftOrdinalsUp(@Param("fromOrdinal") int fromOrdinal,
                         @Param("excludeId") Long excludeId,
                         @Param("formKey") String formKey,
                         @Param("formVersion") int formVersion);

    /** Check whether any other question in the same form/version occupies the given ordinal. */
    boolean existsByOrdinalAndFormKeyAndFormVersionAndIdNot(int ordinal, String formKey, int formVersion, Long id);

    @Query("""
        SELECT q FROM Question q
        WHERE (:active IS NULL OR q.active = :active)
          AND (:formKey IS NULL OR q.formKey = :formKey)
          AND (:formVersion IS NULL OR q.formVersion = :formVersion)
        ORDER BY q.formKey ASC, q.formVersion ASC, q.sectionKey ASC, q.ordinal ASC, q.id ASC
        """)
    List<Question> findByFilters(
            @Param("active") Boolean active,
            @Param("formKey") String formKey,
            @Param("formVersion") Integer formVersion
    );
}
