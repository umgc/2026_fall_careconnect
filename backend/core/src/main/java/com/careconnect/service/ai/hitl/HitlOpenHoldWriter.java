package com.careconnect.service.ai.hitl;

import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.repository.ai.hitl.AiHeldItemRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Inserts open HITL holds in an independent transaction so unique-index races
 * ({@code DataIntegrityViolationException}) roll back only this insert and do not
 * mark the caller's transaction rollback-only.
 *
 * <p>Extracted from {@link HitlService} so {@link Propagation#REQUIRES_NEW} is
 * applied through the Spring proxy (self-invocation would silently ignore it).
 *
 * <p>Tradeoff: when the outer Ask / confirm transaction later rolls back, the
 * hold row committed here can remain {@code PENDING_REVIEW} until TTL expiry or
 * reviewer action (orphan open hold). That is preferred over poisoning the
 * caller's transaction on a unique-index race.
 */
@Service
public class HitlOpenHoldWriter {

    private final AiHeldItemRepository heldItemRepository;

    public HitlOpenHoldWriter(final AiHeldItemRepository heldItemRepository) {
        this.heldItemRepository = heldItemRepository;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public AiHeldItem insertOpenHold(final AiHeldItem item) {
        return heldItemRepository.saveAndFlush(item);
    }
}
