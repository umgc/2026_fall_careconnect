package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

import lombok.Getter;
import lombok.Setter;

/**
 * Durable per-call transcript archive generation and purge fence.
 */
@Entity
@Table(name = "call_transcript_archive_lifecycle")
@Getter
@Setter
public class CallTranscriptArchiveLifecycle {

    @Id
    @Column(name = "call_id", length = 120, nullable = false)
    private String callId;

    @Column(name = "generation", nullable = false)
    private long generation;

    @Column(name = "purged", nullable = false)
    private boolean purged;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;
}
