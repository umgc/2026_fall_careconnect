package com.careconnect.repository;

import com.careconnect.model.CallParticipant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CallParticipantRepository extends JpaRepository<CallParticipant, Long> {
    Optional<CallParticipant> findByCallSessionIdAndUserId(Long callSessionId, Long userId);
    List<CallParticipant> findByCallSessionId(Long callSessionId);
}
