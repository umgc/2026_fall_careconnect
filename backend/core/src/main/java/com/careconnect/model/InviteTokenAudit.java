package com.careconnect.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Immutable audit record for an invite token lifecycle event.
 *
 * Issue #53 acceptance criterion: "Invite creation is permission-gated and audited."
 * Every CREATED / VIEWED / ACCEPTED / EXPIRED / REVOKED event writes one row here,
 * giving end-to-end traceability from creation through expiration.
 */
@Entity
@Table(name = "invite_token_audit")
public class InviteTokenAudit {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "token_id", nullable = false)
    private Long tokenId;

    @Column(name = "event_type", nullable = false, length = 40)
    private String eventType;

    @Column(name = "actor_user_id")
    private Long actorUserId;

    @Column(name = "actor_ip", length = 45)
    private String actorIp;

    @Column(name = "detail", length = 1000)
    private String detail;

    @Column(name = "occurred_at", nullable = false)
    private LocalDateTime occurredAt = LocalDateTime.now();

    // Event type constants
    public static final String EVENT_CREATED  = "CREATED";
    public static final String EVENT_VIEWED   = "VIEWED";
    public static final String EVENT_ACCEPTED = "ACCEPTED";
    public static final String EVENT_EXPIRED  = "EXPIRED";
    public static final String EVENT_REVOKED  = "REVOKED";

    public InviteTokenAudit() {}

    public InviteTokenAudit(Long tokenId, String eventType, Long actorUserId,
                            String actorIp, String detail) {
        this.tokenId = tokenId;
        this.eventType = eventType;
        this.actorUserId = actorUserId;
        this.actorIp = actorIp;
        this.detail = detail;
        this.occurredAt = LocalDateTime.now();
    }

    @PrePersist
    protected void onCreate() {
        if (occurredAt == null) occurredAt = LocalDateTime.now();
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getTokenId() { return tokenId; }
    public void setTokenId(Long tokenId) { this.tokenId = tokenId; }

    public String getEventType() { return eventType; }
    public void setEventType(String eventType) { this.eventType = eventType; }

    public Long getActorUserId() { return actorUserId; }
    public void setActorUserId(Long actorUserId) { this.actorUserId = actorUserId; }

    public String getActorIp() { return actorIp; }
    public void setActorIp(String actorIp) { this.actorIp = actorIp; }

    public String getDetail() { return detail; }
    public void setDetail(String detail) { this.detail = detail; }

    public LocalDateTime getOccurredAt() { return occurredAt; }
    public void setOccurredAt(LocalDateTime occurredAt) { this.occurredAt = occurredAt; }
}
