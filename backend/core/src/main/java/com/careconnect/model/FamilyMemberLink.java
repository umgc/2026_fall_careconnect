package com.careconnect.model;

import jakarta.persistence.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "family_member_link")
public class FamilyMemberLink {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "family_user_id")
    private User familyUser;

    @ManyToOne
    @JoinColumn(name = "patient_user_id")
    private User patientUser;

    // Denormalized patient_id for faster queries (avoiding joins)
    @Column(name = "patient_id")
    private Long patientId;

    @ManyToOne
    @JoinColumn(name = "granted_by")
    private User grantedBy;

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

    @Column(name = "relationship")
    private String relationship; // "Son", "Daughter", "Spouse", etc.

    // Constructors
    public FamilyMemberLink() {
    }

    public FamilyMemberLink(User familyUser, User patientUser, User grantedBy, String relationship) {
        this.familyUser = familyUser;
        this.patientUser = patientUser;
        this.grantedBy = grantedBy;
        this.relationship = relationship;
    }

    public FamilyMemberLink(User familyUser, User patientUser, User grantedBy, String relationship, LinkType linkType) {
        this.familyUser = familyUser;
        this.patientUser = patientUser;
        this.grantedBy = grantedBy;
        this.relationship = relationship;
        this.linkType = linkType;
    }

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
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

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public User getFamilyUser() {
        return familyUser;
    }

    public void setFamilyUser(User familyUser) {
        this.familyUser = familyUser;
    }

    public User getPatientUser() {
        return patientUser;
    }

    public void setPatientUser(User patientUser) {
        this.patientUser = patientUser;
        // Auto-populate patientId when patientUser is set
        if (patientUser != null) {
            // Find patient by user to get patient ID
            // This will be handled in the service layer
        }
    }

    public Long getPatientId() {
        return patientId;
    }

    public void setPatientId(Long patientId) {
        this.patientId = patientId;
    }

    public User getGrantedBy() {
        return grantedBy;
    }

    public void setGrantedBy(User grantedBy) {
        this.grantedBy = grantedBy;
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

    public String getRelationship() {
        return relationship;
    }

    public void setRelationship(String relationship) {
        this.relationship = relationship;
    }

    public enum LinkStatus {
        ACTIVE, SUSPENDED, REVOKED, EXPIRED
    }

    public enum LinkType {
        PERMANENT, TEMPORARY, EMERGENCY
    }
}
