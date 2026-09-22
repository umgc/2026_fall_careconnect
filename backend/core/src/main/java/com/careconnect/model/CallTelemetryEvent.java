package com.careconnect.model;

import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import com.careconnect.config.UtcLocalDateTimeSerializer;
import com.careconnect.config.UtcWallClockLocalDateTimeConverter;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Persisted telemetry event captured for a call lifecycle or sentiment workflow.
 */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "call_telemetry_events",
        indexes = {
                @Index(name = "idx_call_telemetry_call_id", columnList = "call_id"),
                @Index(name = "idx_call_telemetry_actor", columnList = "actor_user_id"),
                @Index(name = "idx_call_telemetry_target", columnList = "target_user_id"),
                @Index(name = "idx_call_telemetry_occurred_at", columnList = "occurred_at")
        })
public class CallTelemetryEvent extends Auditable {

    /**
     * Maximum length for call identifier columns.
     */
    private static final int CALL_ID_LENGTH = 120;

    /**
     * Maximum length for event type values.
     */
    private static final int EVENT_TYPE_LENGTH = 80;

    /**
     * Maximum length for event source values.
     */
    private static final int EVENT_SOURCE_LENGTH = 40;

    /**
     * Maximum length for channel and capture mode values.
     */
    private static final int CHANNEL_LENGTH = 40;

    /**
     * Maximum length for status values.
     */
    private static final int STATUS_LENGTH = 20;

    /**
     * Database identifier for the telemetry event row.
     */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Call identifier associated with the telemetry event.
     */
    @Column(name = "call_id", length = CALL_ID_LENGTH)
    private String callId;

    /**
     * Event type captured for the call telemetry record.
     */
    @Column(name = "event_type", nullable = false, length = EVENT_TYPE_LENGTH)
    private String eventType;

    /**
     * Source subsystem that emitted the telemetry event.
     */
    @Column(name = "event_source", nullable = false, length = EVENT_SOURCE_LENGTH)
    private String eventSource;

    /**
     * Sentiment or transport channel associated with the event.
     */
    @Column(name = "channel", length = CHANNEL_LENGTH)
    private String channel;

    /**
     * User identifier of the actor associated with the event.
     */
    @Column(name = "actor_user_id")
    private Long actorUserId;

    /**
     * User identifier of the target associated with the event.
     */
    @Column(name = "target_user_id")
    private Long targetUserId;

    /**
     * Capture mode recorded for the telemetry event.
     */
    @Column(name = "capture_mode", length = CHANNEL_LENGTH)
    private String captureMode;

    /**
     * Status value recorded for the telemetry event.
     */
    @Column(name = "status", length = STATUS_LENGTH)
    private String status;

    /**
     * Numerical sentiment score associated with the event.
     */
    @Column(name = "sentiment_score")
    private Double sentimentScore;

    /**
     * Sentiment label associated with the event.
     */
    @Column(name = "sentiment_label", length = CHANNEL_LENGTH)
    private String sentimentLabel;

    /**
     * Free-form notes associated with the sentiment result.
     */
    @Column(name = "sentiment_notes", columnDefinition = "TEXT")
    private String sentimentNotes;

    /**
     * Analysis timestamp returned by the sentiment subsystem.
     */
    @Column(name = "analysis_timestamp")
    private Long analysisTimestamp;

    /**
     * Serialized event payload captured as JSON text.
     */
    @Column(name = "payload_json", columnDefinition = "TEXT")
    private String payloadJson;

    /**
     * Serialized metadata captured as JSON text.
     */
    @Column(name = "metadata_json", columnDefinition = "TEXT")
    private String metadataJson;

    /**
     * Error details captured for the telemetry event.
     */
    @Column(name = "error_message", columnDefinition = "TEXT")
    private String errorMessage;

    /**
     * Timestamp when the telemetry event occurred (UTC wall-clock).
     */
    @Column(name = "occurred_at", nullable = false)
    @Convert(converter = UtcWallClockLocalDateTimeConverter.class)
    @JsonSerialize(using = UtcLocalDateTimeSerializer.class)
    private LocalDateTime occurredAt;
}
