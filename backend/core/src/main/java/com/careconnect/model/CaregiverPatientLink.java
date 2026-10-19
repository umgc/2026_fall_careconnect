package com.careconnect.model;

import jakarta.persistence.*;

import java.time.LocalDateTime;

import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;


@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "caregiver_patient_link")
public class CaregiverPatientLink {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "caregiver_user_id")
    private User caregiverUser;

    @ManyToOne
    @JoinColumn(name = "patient_user_id")
    private User patientUser;

    @ManyToOne
    @JoinColumn(name = "created_by")
    private User createdBy;

    @Column(name = "created_at")
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "updated_at")
    private LocalDateTime updatedAt = LocalDateTime.now();

    @Column(name = "status")
    @Enumerated(EnumType.STRING)
    private LinkStatus status = LinkStatus.ACTIVE;

    @Column(name = "link_type")
    @Enumerated(EnumType.STRING)
    private LinkType linkType = LinkType.PERMANENT;

    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

    @Column(name = "notes")
    private String notes;

    // Constructor for creating caregiver-patient links
    public CaregiverPatientLink(User caregiverUser, User patientUser, User createdBy, LinkType linkType) {
        this.caregiverUser = caregiverUser;
        this.patientUser = patientUser;
        this.createdBy = createdBy;
        this.linkType = linkType;
    }

    // Helper methods
    public boolean isActive() {
        if (status != LinkStatus.ACTIVE) {
            return false;
        }
        if (expiresAt != null && LocalDateTime.now().isAfter(expiresAt)) {
            return false;
        }
        return true;
    }

    public boolean isExpired() {
        return expiresAt != null && LocalDateTime.now().isAfter(expiresAt);
    }

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public User getCaregiverUser() {
        return caregiverUser;
    }

    public void setCaregiverUser(User caregiverUser) {
        this.caregiverUser = caregiverUser;
    }

    public User getPatientUser() {
        return patientUser;
    }

    public void setPatientUser(User patientUser) {
        this.patientUser = patientUser;
    }

    public User getCreatedBy() {
        return createdBy;
    }

    public void setCreatedBy(User createdBy) {
        this.createdBy = createdBy;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    public LinkStatus getStatus() {
        return status;
    }

    public void setStatus(LinkStatus status) {
        this.status = status;
        this.updatedAt = LocalDateTime.now();
    }

    public LinkType getLinkType() {
        return linkType;
    }

    public void setLinkType(LinkType linkType) {
        this.linkType = linkType;
    }

    public LocalDateTime getExpiresAt() {
        return expiresAt;
    }

    public void setExpiresAt(LocalDateTime expiresAt) {
        this.expiresAt = expiresAt;
    }

    public String getNotes() {
        return notes;
    }

    public void setNotes(String notes) {
        this.notes = notes;
    }

    public enum LinkStatus {
        PENDING, ACTIVE, SUSPENDED, REVOKED, EXPIRED, REJECTED
    }

    public enum LinkType {
        PERMANENT, TEMPORARY, EMERGENCY
    }
}
