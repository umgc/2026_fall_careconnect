package com.careconnect.service.ai.hitl;

/**
 * Invalid HITL state transition (e.g. release when not pending).
 */
public class HitlConflictException extends RuntimeException {
    public HitlConflictException(final String message) {
        super(message);
    }
}
