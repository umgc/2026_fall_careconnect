package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class CernerAuthStateStoreTest {

    @Test
    void issuedStateIsOpaqueAndSingleUse() {
        final CernerAuthStateStore store = new CernerAuthStateStore();

        final String state = store.issue(42L, "pkce-verifier", "web");
        final CernerAuthStateStore.Entry entry = store.consume(state);

        assertThat(state).hasSize(32).doesNotContain("pkce-verifier");
        assertThat(entry.userId()).isEqualTo(42L);
        assertThat(entry.verifier()).isEqualTo("pkce-verifier");
        assertThat(entry.returnMode()).isEqualTo("web");
        assertThat(store.consume(state)).isNull();
    }

    @Test
    void nullBlankAndUnknownStatesAreRejected() {
        final CernerAuthStateStore store = new CernerAuthStateStore();

        assertThat(store.consume(null)).isNull();
        assertThat(store.consume(" ")).isNull();
        assertThat(store.consume("unknown-state")).isNull();
    }
}
