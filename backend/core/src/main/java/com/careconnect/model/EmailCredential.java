package com.careconnect.model;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "email_credentials")
public class EmailCredential {
    public enum Provider { GMAIL, OUTLOOK }

    /**
     * Connection lifecycle for OAuth mail providers (Task 3.14.9).
     */
    public enum Status {
        ACTIVE,
        NEEDS_REAUTH,
        DISCONNECTED
    }

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false) private String userId;
    @Enumerated(EnumType.STRING) @Column(nullable = false)
    private Provider provider;

    @Lob private String accessTokenEnc;
    @Lob private String refreshTokenEnc;
    private Instant expiresAt;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private Status status = Status.ACTIVE;

    @Column(name = "sync_enabled", nullable = false)
    private boolean syncEnabled = true;

    @Column(name = "last_error", length = 512)
    private String lastError;

    @Column(name = "last_error_at")
    private Instant lastErrorAt;

    @Column(name = "reauth_notified_at")
    private Instant reauthNotifiedAt;

    // getters/setters
    public Long getId() { return id; }
    public String getUserId() { return userId; }
    public void setUserId(String u) { userId = u; }
    public Provider getProvider() { return provider; }
    public void setProvider(Provider p) { provider = p; }
    public String getAccessTokenEnc() { return accessTokenEnc; }
    public void setAccessTokenEnc(String s) { accessTokenEnc = s; }
    public String getRefreshTokenEnc() { return refreshTokenEnc; }
    public void setRefreshTokenEnc(String s) { refreshTokenEnc = s; }
    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant t) { expiresAt = t; }

    public Status getStatus() {
        return status == null ? Status.ACTIVE : status;
    }

    public void setStatus(Status status) {
        this.status = status == null ? Status.ACTIVE : status;
    }

    public boolean isSyncEnabled() {
        return syncEnabled;
    }

    public void setSyncEnabled(boolean syncEnabled) {
        this.syncEnabled = syncEnabled;
    }

    public String getLastError() {
        return lastError;
    }

    public void setLastError(String lastError) {
        this.lastError = lastError;
    }

    public Instant getLastErrorAt() {
        return lastErrorAt;
    }

    public void setLastErrorAt(Instant lastErrorAt) {
        this.lastErrorAt = lastErrorAt;
    }

    public Instant getReauthNotifiedAt() {
        return reauthNotifiedAt;
    }

    public void setReauthNotifiedAt(Instant reauthNotifiedAt) {
        this.reauthNotifiedAt = reauthNotifiedAt;
    }

    public boolean allowsSync() {
        return isSyncEnabled() && getStatus() == Status.ACTIVE;
    }
}
