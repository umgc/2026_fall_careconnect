// com.careconnect.repository.AnswerRepository
package com.careconnect.repository;

import com.careconnect.model.Answer;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AnswerRepository extends JpaRepository<Answer, Long> {
    boolean existsByCheckIn_IdAndQuestion_Id(Long checkInId, Long questionId);
    List<Answer> findByCheckIn_Id(Long checkInId);
}
