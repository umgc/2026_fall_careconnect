package com.careconnect.repository;

import com.careconnect.model.InviteTokenAudit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface InviteTokenAuditRepository extends JpaRepository<InviteTokenAudit, Long> {

    /** Full lifecycle trail for a single token, newest first. */
    List<InviteTokenAudit> findByTokenIdOrderByOccurredAtDesc(Long tokenId);
}
