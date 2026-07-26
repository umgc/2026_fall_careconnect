package com.careconnect.service.ai.hitl;

/**
 * Held item missing.
 */
public class HitlNotFoundException extends RuntimeException {
    public HitlNotFoundException(final String message) {
        super(message);
    }
}
