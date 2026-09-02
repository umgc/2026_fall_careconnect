package com.careconnect.model.evv;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

/**
 * Entity representing location data for EVV record check-ins and check-outs
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "evv_record_location")
public class EvvRecordLocation {

    @Id
    @Column(columnDefinition = "uuid")
    private UUID id;

    @Column(name = "evv_record_id", nullable = false)
    private Long evvRecordId;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false, length = 20)
    private EvvLocationRole role;

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 20)
    private EvvLocationType type;

    @Column(name = "latitude", precision = 9, scale = 6)
    private BigDecimal latitude;

    @Column(name = "longitude", precision = 9, scale = 6)
    private BigDecimal longitude;

    @Column(name = "accuracy_m", precision = 6, scale = 2)
    private BigDecimal accuracyM;

    @Convert(disableConversion = true)
    @Column(name = "address_snapshot_json", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> addressSnapshotJson;

    /**
     * Reason GPS could not be captured; required when type != GPS
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "no_gps_reason", length = 50)
    private NoGpsReason noGpsReason;

    /**
     * Free-form address for MANUAL location type (e.g. community or facility visits)
     */
    @Column(name = "manual_address", length = 500)
    private String manualAddress;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = OffsetDateTime.now();
        }
    }

    /**
     * Validate the location data based on type.
     * Federal EVV regulations require a noGpsReason whenever GPS is not used.
     */
    public void validate() {
        if (type == EvvLocationType.GPS) {
            if (latitude == null || longitude == null) {
                throw new IllegalStateException("GPS location requires latitude and longitude");
            }
        } else if (type == EvvLocationType.PATIENT_ADDRESS) {
            if (addressSnapshotJson == null || addressSnapshotJson.isEmpty()) {
                throw new IllegalStateException("PATIENT_ADDRESS location requires address snapshot");
            }
            if (noGpsReason == null) {
                throw new IllegalStateException("PATIENT_ADDRESS location requires a noGpsReason (federal EVV requirement)");
            }
        } else if (type == EvvLocationType.MANUAL) {
            if (manualAddress == null || manualAddress.isBlank()) {
                throw new IllegalStateException("MANUAL location requires a manual address");
            }
            if (noGpsReason == null) {
                throw new IllegalStateException("MANUAL location requires a noGpsReason (federal EVV requirement)");
            }
        }
    }
}

