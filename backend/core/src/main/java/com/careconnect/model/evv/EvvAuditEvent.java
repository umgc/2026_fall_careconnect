package com.careconnect.model.evv;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.Map;

@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "evv_audit_event")
public class EvvAuditEvent {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "evv_record_id", nullable = false)
    private EvvRecord evvRecord;

    @Column(name = "event_type", nullable = false)
    private String eventType;
    @Column(name = "event_time", nullable = false)
    private OffsetDateTime eventTime;
    @Column(name = "actor_user_id", nullable = false)
    private Long actorUserId;

    @Convert(disableConversion = true)
    @Column(name = "device_info", columnDefinition = "jsonb")
    private Map<String, Object> deviceInfo;

    @Convert(disableConversion = true)
    @Column(name = "details", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> details;

    @PrePersist
    void onCreate() {
        if (eventTime == null) eventTime = OffsetDateTime.now();
    }
}
