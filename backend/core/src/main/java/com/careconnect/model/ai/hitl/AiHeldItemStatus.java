package com.careconnect.model.ai.hitl;

/**
 * Lifecycle states for an Ask AI Tier-2 held item (REQ-SC-4 / REQ-SC-6).
 */
public enum AiHeldItemStatus {
    PENDING_REVIEW,
    APPROVED_AS_IS,
    APPROVED_EDITED,
    REJECTED,
    EXPIRED,
    DELIVERED
}
