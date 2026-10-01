package com.careconnect.model;

import jakarta.persistence.*;

import java.time.Instant;

@Entity
@Table(name = "usps_digest_cache")
public class USPSDigestCache {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String userId;
    @Lob
    @Column(nullable = false)
    private String payloadJson;
    private Instant digestDate;
    @Column(nullable = false)
    private Instant expiresAt;

    // getters/setters
    public Long getId() {
        return id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String s) {
        userId = s;
    }

    public String getPayloadJson() {
        return payloadJson;
    }

    public void setPayloadJson(String s) {
        payloadJson = s;
    }

    public Instant getDigestDate() {
        return digestDate;
    }

    public void setDigestDate(Instant t) {
        digestDate = t;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public void setExpiresAt(Instant t) {
        expiresAt = t;
    }
}
