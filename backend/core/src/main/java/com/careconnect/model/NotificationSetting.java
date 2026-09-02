package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(name = "notification_setting")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class NotificationSetting {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private Long userId;

    @Builder.Default
    private boolean gamification = true;
    @Builder.Default
    private boolean emergency = true;
    @Builder.Default
    private boolean videoCall = true;
    @Builder.Default
    private boolean audioCall = true;
    @Builder.Default
    private boolean sms = true;
    @Builder.Default
    private boolean significantVitals = true;

    @Column(nullable = false)
    private Instant createdAt;
    @Column(nullable = false)
    private Instant updatedAt;

    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = Instant.now();
    }
}
