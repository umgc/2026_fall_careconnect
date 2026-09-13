package com.careconnect.service.ehr;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

class EpicAuthStateStoreTest {

    private final EpicAuthStateStore store = new EpicAuthStateStore();

    @Test
    void issueThenConsume_returnsUserAndVerifier() {
        String state = store.issue(42L, "verifier-abc");
        EpicAuthStateStore.Entry entry = store.consume(state);
        assertNotNull(entry);
        assertEquals(42L, entry.userId());
        assertEquals("verifier-abc", entry.codeVerifier());
    }

    @Test
    void consume_isSingleUse() {
        String state = store.issue(1L, "v");
        assertNotNull(store.consume(state));
        assertNull(store.consume(state), "state must be single-use (replay defense)");
    }

    @Test
    void consume_unknownOrNull_returnsNull() {
        assertNull(store.consume("nope"));
        assertNull(store.consume(null));
        assertNull(store.consume(""));
    }
}
