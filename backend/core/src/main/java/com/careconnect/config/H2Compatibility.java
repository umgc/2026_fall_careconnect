package com.careconnect.config;

/**
 * H2 stand-ins for PostgreSQL helpers used by native SQL in integration tests.
 *
 * <p>Single-process H2 tests do not need real advisory locking; aliases exist so native
 * {@code SELECT pg_advisory_xact_lock(...)} statements parse and execute.
 */
public final class H2Compatibility {

    private H2Compatibility() {
    }

    /**
     * Mirrors {@code hashtextextended(text, seed)} enough for deterministic lock keys.
     */
    public static long hashTextExtended(final String text, final Long seed) {
        final long seedValue = seed == null ? 0L : seed;
        if (text == null) {
            return seedValue;
        }
        return (((long) text.hashCode()) << 32) ^ seedValue;
    }

    /**
     * No-op stand-in for {@code pg_advisory_xact_lock(bigint)}.
     */
    public static void pgAdvisoryXactLock(final Long key) {
        // Intentionally empty for H2.
    }
}
