package com.careconnect.repository.ai.ask;

import com.careconnect.model.ai.ask.AiAskShareRecipient;

import java.util.Collection;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface AiAskShareRecipientRepository
        extends JpaRepository<AiAskShareRecipient, AiAskShareRecipient.Pk> {

    void deleteByShareId(UUID shareId);

    long countByShareIdAndUserIdIn(UUID shareId, Collection<Long> userIds);
}
