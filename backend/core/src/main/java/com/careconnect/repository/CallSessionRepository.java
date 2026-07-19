package com.careconnect.repository;

import com.careconnect.model.CallSession;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CallSessionRepository extends JpaRepository<CallSession, Long> {
    Optional<CallSession> findByCallId(String callId);
}
