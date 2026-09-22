package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * Persisted telemetry event captured from the client or server.
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "telemetry_events")
public class TelemetryEvent {

    /**
     * Maximum length for the event name column.
     */
    private static final int EVENT_NAME_LENGTH = 128;

    /**
     * Maximum length for the session identifier column.
     */
    private static final int SESSION_ID_LENGTH = 64;

    /**
     * Maximum length for the trace identifier column.
     */
    private static final int TRACE_ID_LENGTH = 64;

    /**
     * Maximum length for the span identifier column.
     */
    private static final int SPAN_ID_LENGTH = 32;

    /**
     * Database primary key.
     */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Telemetry event name.
     */
    @Column(name = "event_name", nullable = false, length = EVENT_NAME_LENGTH)
    private String eventName;

    /**
     * Timestamp when the event occurred.
     */
    @Column(name = "event_time", nullable = false)
    private OffsetDateTime eventTime;

    /**
     * Session identifier associated with the event.
     */
    @Column(name = "session_id", length = SESSION_ID_LENGTH)
    private String sessionId;

    /**
     * Trace identifier associated with the event.
     */
    @Column(name = "trace_id", length = TRACE_ID_LENGTH)
    private String traceId;

    /**
     * Span identifier associated with the event.
     */
    @Column(name = "span_id", length = SPAN_ID_LENGTH)
    private String spanId;

    /**
     * Structured device metadata stored as JSON.
     */
    @Convert(disableConversion = true)
    @Column(name = "device_info", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> deviceInfo;

    /**
     * Structured telemetry details stored as JSON.
     */
    @Convert(disableConversion = true)
    @Column(name = "details", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> details;

    @SuppressWarnings("EI_EXPOSE_REP2")
    private static Map<String, Object> mutableCopy(final Map<String, Object> source) {
        return source == null ? null : new LinkedHashMap<>(source);
    }

    private static Map<String, Object> immutableCopy(final Map<String, Object> source) {
        return source == null
                ? null
                : Collections.unmodifiableMap(new LinkedHashMap<>(source));
    }

    public Map<String, Object> getDeviceInfo() {
        return immutableCopy(deviceInfo);
    }

    public void setDeviceInfo(final Map<String, Object> deviceInfo) {
        this.deviceInfo = mutableCopy(deviceInfo);
    }

    public Map<String, Object> getDetails() {
        return immutableCopy(details);
    }

    public void setDetails(final Map<String, Object> details) {
        this.details = mutableCopy(details);
    }

    /**
     * Initializes the event timestamp when a new entity is first persisted.
     */
    @PrePersist
    void onCreate() {
        if (eventTime == null) {
            eventTime = OffsetDateTime.now();
        }
    }
}
