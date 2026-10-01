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
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Durable cleanup command for AWS resources created before persistence failed.
 */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(name = "recording_compensation_outbox")
public class RecordingCompensation {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "call_id", nullable = false, length = 120)
    private String callId;

    @Column(name = "generation", nullable = false)
    private long generation;

    @Column(name = "resource_type", nullable = false, length = 32)
    private String resourceType;

    @Column(name = "aws_resource_id", nullable = false, length = 255)
    private String awsResourceId;

    @Column(name = "s3_bucket", length = 255)
    private String s3Bucket;

    @Column(name = "s3_prefix", length = 500)
    private String s3Prefix;

    @Column(name = "state", nullable = false, length = 20)
    private String state;

    @Column(name = "claim_token")
    private UUID claimToken;

    @Column(name = "claimed_until")
    private LocalDateTime claimedUntil;

    @Column(name = "attempt_count", nullable = false)
    private int attemptCount;

    @Column(name = "next_attempt_at", nullable = false)
    private LocalDateTime nextAttemptAt;

    @Column(name = "last_error", columnDefinition = "TEXT")
    private String lastError;

    @Column(name = "completed_at")
    private LocalDateTime completedAt;
}
