package com.careconnect.repository;

import com.careconnect.model.CheckInQuestion;
import com.careconnect.model.CheckInQuestionId;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.JpaRepository;
import com.careconnect.dto.QuestionDTO;

import java.util.List;
import java.util.Set;

public interface CheckInQuestionRepository extends JpaRepository<CheckInQuestion, CheckInQuestionId> {
    interface CheckInQuestionCountProjection {
        Long getCheckInId();
        long getQuestionCount();
    }

    List<CheckInQuestion> findByCheckIn_IdOrderByOrdinalAsc(Long checkInId);
    boolean existsByCheckIn_IdAndQuestion_Id(Long checkInId, Long questionId);
    long countByCheckIn_Id(Long checkInId);

    @Query("""
            SELECT ciq.checkIn.id AS checkInId, COUNT(ciq) AS questionCount
            FROM CheckInQuestion ciq
            WHERE ciq.checkIn.id IN :checkInIds
            GROUP BY ciq.checkIn.id
            """)
    List<CheckInQuestionCountProjection> countByCheckInIds(@Param("checkInIds") Set<Long> checkInIds);

    @Query("""
            SELECT new com.careconnect.dto.QuestionDTO(
                q.id,
                ciq.promptSnapshot,
                ciq.typeSnapshot,
                ciq.required,
                true,
                ciq.ordinal
            )
            FROM CheckInQuestion ciq
            JOIN ciq.question q
            WHERE ciq.checkIn.id = :checkInId
            ORDER BY ciq.ordinal ASC
            """)
    List<QuestionDTO> findSnapshotQuestionDtosByCheckInId(@Param("checkInId") Long checkInId);
}
