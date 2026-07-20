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
    List<Question> findAllByActiveTrueOrderByOrdinalAsc();

    // (Optional niceties)
    List<Question> findAllByActiveTrue();
    List<Question> findAllByActiveFalse();

    List<Question> findAllByOrderByOrdinalAsc();

    List<Question> findAllByActiveFalseOrderByOrdinalAsc();

    /** Shift all questions at or above the given ordinal up by 1, excluding the question being updated. */
    @Modifying
    @Query("UPDATE Question q SET q.ordinal = q.ordinal + 1 WHERE q.ordinal >= :fromOrdinal AND q.id <> :excludeId")
    void shiftOrdinalsUp(@Param("fromOrdinal") int fromOrdinal, @Param("excludeId") Long excludeId);

    /** Check whether any other question (excluding the current id) occupies the given ordinal. */
    boolean existsByOrdinalAndIdNot(int ordinal, Long id);
}
