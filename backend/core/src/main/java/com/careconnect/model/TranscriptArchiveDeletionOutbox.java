package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.Setter;

/** Durable outbox for deleting transcript archive objects after commit. */
@Entity
@Table(name = "transcript_archive_deletion_outbox")
@Getter
@Setter
public class TranscriptArchiveDeletionOutbox {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "storage_key", length = 512, nullable = false, unique = true)
    private String storageKey;

    @Column(name = "attempts", nullable = false)
    private int attempts;

    @Column(name = "next_attempt_at", nullable = false)
    private LocalDateTime nextAttemptAt;

    @Column(name = "claimed_until")
    private LocalDateTime claimedUntil;

    @Column(name = "claim_token")
    private UUID claimToken;

    @Column(name = "last_error", length = 1000)
    private String lastError;

    @Column(name = "dead_lettered_at")
    private LocalDateTime deadLetteredAt;

    @Column(name = "terminal_error", length = 1000)
    private String terminalError;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;
}
