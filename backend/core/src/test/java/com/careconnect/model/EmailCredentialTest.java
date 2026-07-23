package com.careconnect.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class EmailCredentialTest {

    // ─── Default constructor ──────────────────────────────────────────────────

    @Test
    void defaultConstructor_createsInstance() throws Exception {
        final EmailCredential cred = new EmailCredential();
        assertThat(cred).isNotNull();
        assertThat(cred.getId()).isNull();
    }

    // ─── Setters / Getters ────────────────────────────────────────────────────

    @Test
    void settersAndGetters_updateFields() throws Exception {
        final EmailCredential cred = new EmailCredential();
        final Instant expires = Instant.parse("2025-12-31T23:59:59Z");

        cred.setUserId("user-001");
        cred.setProvider(EmailCredential.Provider.GMAIL);
        cred.setAccessTokenEnc("enc-access-token");
        cred.setRefreshTokenEnc("enc-refresh-token");
        cred.setExpiresAt(expires);

        assertThat(cred.getUserId()).isEqualTo("user-001");
        assertThat(cred.getProvider()).isEqualTo(EmailCredential.Provider.GMAIL);
        assertThat(cred.getAccessTokenEnc()).isEqualTo("enc-access-token");
        assertThat(cred.getRefreshTokenEnc()).isEqualTo("enc-refresh-token");
        assertThat(cred.getExpiresAt()).isEqualTo(expires);
    }

    // ─── Provider enum ────────────────────────────────────────────────────────

    @Test
    void providerEnum_containsAllValues() throws Exception {
        assertThat(EmailCredential.Provider.values()).containsExactly(
                EmailCredential.Provider.GMAIL,
                EmailCredential.Provider.OUTLOOK
        );
    }

    @Test
    void providerEnum_outlook() throws Exception {
        final EmailCredential cred = new EmailCredential();
        cred.setProvider(EmailCredential.Provider.OUTLOOK);
        assertThat(cred.getProvider()).isEqualTo(EmailCredential.Provider.OUTLOOK);
    }

    @Test
    void defaultsAllowSyncUntilRevoked() {
        final EmailCredential cred = new EmailCredential();
        assertThat(cred.getStatus()).isEqualTo(EmailCredential.Status.ACTIVE);
        assertThat(cred.isSyncEnabled()).isTrue();
        assertThat(cred.allowsSync()).isTrue();

        cred.setStatus(EmailCredential.Status.NEEDS_REAUTH);
        cred.setSyncEnabled(false);
        assertThat(cred.allowsSync()).isFalse();
    }
}
