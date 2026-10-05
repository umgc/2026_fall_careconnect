package com.careconnect.model;

import jakarta.persistence.*;

import java.time.LocalDateTime;

/**
 * An invite token scoped to a single {@link FamilyMemberLink} (care circle).
 * <p>
 * Issue #53: each active link gets a unique, trackable invite token whose
 * lifecycle runs PENDING -> ACCEPTED | EXPIRED | REVOKED.
 * <p>
 * Security: the raw token is NEVER stored. We persist:
 * - tokenLookup: a non-secret prefix used to find the row quickly, and
 * - tokenHash:   a one-way BCrypt hash (via TokenHashService) we verify against.
 * The raw token only appears in the create response and the share URL.
 * <p>
 * Follows the existing model conventions in this codebase: plain JPA entity,
 * explicit getters/setters, LocalDateTime timestamps, inner enums.
 */
@Entity
@Table(name = "invite_token")
public class InviteToken {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Optimistic-lock version. JPA increments this on every update; if two
     * concurrent transactions read the same row and both try to save, the
     * second commit fails with OptimisticLockException. This prevents a
     * double-accept race where two users could both redeem one PENDING token.
     */
    @Version
    @Column(name = "version", nullable = false)
    private Long version;

    @Column(name = "token_lookup", nullable = false, unique = true, length = 32)
    private String tokenLookup;

    @Column(name = "token_hash", nullable = false)
    private String tokenHash;

    // Scope: the care-circle link this token belongs to.
    @Column(name = "link_id", nullable = false)
    private Long linkId;

    @Column(name = "link_type", nullable = false, length = 30)
    @Enumerated(EnumType.STRING)
    private FamilyMemberLink.LinkType linkType;

    @Column(name = "status", nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private Status status = Status.PENDING;

    @Column(name = "invited_email")
    private String invitedEmail;

    // Human-readable reason surfaced by the "Who invited me?" context (issue #59).
    @Column(name = "invite_reason", length = 500)
    private String inviteReason;

    @Column(name = "created_by_user_id", nullable = false)
    private Long createdByUserId;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    @Column(name = "accepted_by_user_id")
    private Long acceptedByUserId;

    @Column(name = "accepted_at")
    private LocalDateTime acceptedAt;

    @Column(name = "revoked_by_user_id")
    private Long revokedByUserId;

    @Column(name = "revoked_at")
    private LocalDateTime revokedAt;

    @Column(name = "revoke_reason", length = 500)
    private String revokeReason;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt = LocalDateTime.now();

    public InviteToken() {
    }

    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        if (createdAt == null) createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    /**
     * True only while the token is PENDING and has not passed its TTL.
     */
    public boolean isUsable() {
        return status == Status.PENDING && !isExpired();
    }

    // ----- Domain helpers --------------------------------------------------

    public boolean isExpired() {
        return expiresAt != null && LocalDateTime.now().isAfter(expiresAt);
    }

    public Long getId() {
        return id;
    }

    // ----- Getters / Setters ----------------------------------------------

    public void setId(Long id) {
        this.id = id;
    }

    public Long getVersion() {
        return version;
    }

    public void setVersion(Long version) {
        this.version = version;
    }

    public String getTokenLookup() {
        return tokenLookup;
    }

    public void setTokenLookup(String tokenLookup) {
        this.tokenLookup = tokenLookup;
    }

    public String getTokenHash() {
        return tokenHash;
    }

    public void setTokenHash(String tokenHash) {
        this.tokenHash = tokenHash;
    }

    public Long getLinkId() {
        return linkId;
    }

    public void setLinkId(Long linkId) {
        this.linkId = linkId;
    }

    public FamilyMemberLink.LinkType getLinkType() {
        return linkType;
    }

    public void setLinkType(FamilyMemberLink.LinkType linkType) {
        this.linkType = linkType;
    }

    public Status getStatus() {
        return status;
    }

    public void setStatus(Status status) {
        this.status = status;
        this.updatedAt = LocalDateTime.now();
    }

    public String getInvitedEmail() {
        return invitedEmail;
    }

    public void setInvitedEmail(String invitedEmail) {
        this.invitedEmail = invitedEmail;
    }

    public String getInviteReason() {
        return inviteReason;
    }

    public void setInviteReason(String inviteReason) {
        this.inviteReason = inviteReason;
    }

    public Long getCreatedByUserId() {
        return createdByUserId;
    }

    public void setCreatedByUserId(Long createdByUserId) {
        this.createdByUserId = createdByUserId;
    }

    public LocalDateTime getExpiresAt() {
        return expiresAt;
    }

    public void setExpiresAt(LocalDateTime expiresAt) {
        this.expiresAt = expiresAt;
    }

    public Long getAcceptedByUserId() {
        return acceptedByUserId;
    }

    public void setAcceptedByUserId(Long acceptedByUserId) {
        this.acceptedByUserId = acceptedByUserId;
    }

    public LocalDateTime getAcceptedAt() {
        return acceptedAt;
    }

    public void setAcceptedAt(LocalDateTime acceptedAt) {
        this.acceptedAt = acceptedAt;
    }

    public Long getRevokedByUserId() {
        return revokedByUserId;
    }

    public void setRevokedByUserId(Long revokedByUserId) {
        this.revokedByUserId = revokedByUserId;
    }

    public LocalDateTime getRevokedAt() {
        return revokedAt;
    }

    public void setRevokedAt(LocalDateTime revokedAt) {
        this.revokedAt = revokedAt;
    }

    public String getRevokeReason() {
        return revokeReason;
    }

    public void setRevokeReason(String revokeReason) {
        this.revokeReason = revokeReason;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    public enum Status {
        PENDING,    // issued, awaiting acceptance
        ACCEPTED,   // redeemed by an invitee
        EXPIRED,    // TTL elapsed before acceptance
        REVOKED     // explicitly cancelled by creator/admin
    }
}
