package com.careconnect.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

import java.util.List;
import java.time.LocalDateTime;
import java.util.ArrayList;

import lombok.*;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
public class Patient {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String firstName;
    private String lastName;

    private String email;
    private String phone;

    private String dob; // LocalDate for better type safety

    @Column(name = "gender")
    @Enumerated(EnumType.STRING)
    private Gender gender;

    @Embedded
    private Address address;

    @OneToOne(cascade = CascadeType.ALL)
    @JoinColumn(name = "user_id")
    private User user;

    @OneToMany(mappedBy = "patient", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JsonIgnore  // Prevent lazy loading issues during JSON serialization
    @Builder.Default
    private List<Allergy> allergies = new ArrayList<>();

    private String relationship; // e.g. "daughter", "client", etc.

    @Column(name = "ma_number", unique = true, length = 64)
    private String maNumber; // Medical Assistance Number for EVV compliance

    // In-Home personalization fields
    @Column(columnDefinition = "TEXT")
    private String likes;

    @Column(columnDefinition = "TEXT")
    private String dislikes;

    @Column(columnDefinition = "TEXT")
    private String habits;

    @Column(columnDefinition = "TEXT")
    private String phobias;

    @Column(name = "preferred_communication_method", length = 32)
    private String preferredCommunicationMethod; // verbal | visual | written | gesture

    @Column(name = "is_alexa_linked", nullable = true) // ← Database column
    private Boolean alexaLinked; // ← Java field name

    // --- inside class Patient ---
    @ManyToOne
    @JoinColumn(name = "primary_care_provider_id")
    private Provider primaryCareProvider;
    @Column(name = "alexa_refresh_token", length = 500, nullable = true)
    private String alexaRefreshToken;
    @Column(name = "alexa_refresh_token_expires_at", nullable = true)
    private LocalDateTime alexaRefreshTokenExpiresAt;
    @Column(name = "alexa_refresh_token_created_at", nullable = true)
    private LocalDateTime alexaRefreshTokenCreatedAt;

    public Provider getPrimaryCareProvider() {
        return primaryCareProvider;
    }

    public void setPrimaryCareProvider(Provider primaryCareProvider) {
        this.primaryCareProvider = primaryCareProvider;
    }

    // Explicit getter for compatibility if Lombok is not processed
    public User getUser() {
        return user;
    }

    public boolean isAlexaLinked() {
        return Boolean.TRUE.equals(alexaLinked);
    }

    public void setAlexaLinked(Boolean alexaLinked) {
        this.alexaLinked = alexaLinked;
    }

    public String getAlexaRefreshToken() {
        return alexaRefreshToken;
    }

    public void setAlexaRefreshToken(String alexaRefreshToken) {
        this.alexaRefreshToken = alexaRefreshToken;
    }

    public LocalDateTime getAlexaRefreshTokenExpiresAt() {
        return alexaRefreshTokenExpiresAt;
    }

    public void setAlexaRefreshTokenExpiresAt(LocalDateTime expiresAt) {
        this.alexaRefreshTokenExpiresAt = expiresAt;
    }

    public LocalDateTime getAlexaRefreshTokenCreatedAt() {
        return alexaRefreshTokenCreatedAt;
    }

    public void setAlexaRefreshTokenCreatedAt(LocalDateTime createdAt) {
        this.alexaRefreshTokenCreatedAt = createdAt;
    }

    // Helper method to check if refresh token is expired
    public boolean isAlexaRefreshTokenExpired() {
        if (alexaRefreshTokenExpiresAt == null) {
            return true;
        }
        return LocalDateTime.now().isAfter(alexaRefreshTokenExpiresAt);
    }
}