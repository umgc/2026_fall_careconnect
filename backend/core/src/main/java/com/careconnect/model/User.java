package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.Builder;
import lombok.Singular;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.Set;
import java.util.HashSet;

// Import RBAC classes
import com.careconnect.security.Role;
import com.careconnect.security.Permission;
import com.careconnect.security.RolePermissionService;

@Entity
@Table(name = "users")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String name;

    @Column(unique = true, nullable = false)
    private String email;

    @Column(nullable = false)
    private String password;

    @Column(name = "password_hash")
    private String passwordHash;

    @Column(name = "last_login_date")
    private LocalDate lastLoginDate;

    @Builder.Default
    @Column(name = "login_streak")
    private Integer loginStreak = 0;

    @Builder.Default
    @Column(name = "leaderboard_opt_in", nullable = true)
    private Boolean leaderboardOptIn = true;

    // --- REFACTORED SECURE DB-DRIVEN RBAC INFRASTRUCTURE ---
    // Swapped direct enum column mapping for a collection table to support future multi-role architectures
   @Singular("role") // <--- Replaced @Builder.Default with @Singular("role")
    @ElementCollection(targetClass = Role.class, fetch = FetchType.EAGER)
    @CollectionTable(
        name = "user_roles",
        joinColumns = @JoinColumn(name = "user_id")
    )
    @Column(name = "role_name", nullable = false)
    @Enumerated(EnumType.STRING)
    private Set<Role> roles = new HashSet<>();

    @Builder.Default
    @Column(name = "email_verified", nullable = false)
    private Boolean isVerified = false;

    private String verificationToken;
    
    @Column(name = "payment_customer_id")
    private String paymentCustomerId;

    @Column(name = "address_line1")
    private String addressLine1;

    @Column(name = "address_line2")
    private String addressLine2;

    @Column(name = "city")
    private String city;

    @Column(name = "state", length = 2)
    private String state; 

    @Column(name = "postal_code")
    private String postalCode;

    @Column(name = "country", length = 2)
    private String country; 

    @Column(name = "address_place_id")
    private String addressPlaceId; 

    @Column(name = "address_formatted")
    private String addressFormatted; 

    @Column(name = "address_latitude")
    private Double addressLatitude;

    @Column(name = "address_longitude")
    private Double addressLongitude;

    private Timestamp createdAt;

    private Timestamp lastLogin;

    private String profileImageUrl;

    @Builder.Default
    @Column(nullable = false)
    private String status = "ACTIVE";

    @Column(name = "phone", length = 20)
    private String phone;

    // ========== BACKWARDS-COMPATIBILITY SEAM LAYERS ==========

    /**
     * Legacy single-role getter layer. Resolves the primary structural 
     * authority from the backend collection layer to prevent integration breaking.
     */
    public Role getRole() {
        if (this.roles == null || this.roles.isEmpty()) {
            return null;
        }
        return this.roles.iterator().next();
    }

    /**
     * Legacy single-role setter layer. Syncs direct scalar assignments 
     * into the multi-value entity set securely.
     */
    public void setRole(Role role) {
        if (this.roles == null) {
            this.roles = new HashSet<>();
        }
        this.roles.clear();
        if (role != null) {
            this.roles.add(role);
        }
    }

    // ========== RBAC Permission Methods ==========

    public Set<Permission> getPermissions() {
        Role activeRole = getRole();
        if (activeRole == null) {
            return Set.of(); 
        }
        return RolePermissionService.getPermissionsForRole(activeRole);
    }

    public boolean hasPermission(Permission permission) {
        Role activeRole = getRole();
        if (activeRole == null || permission == null) {
            return false;
        }
        return RolePermissionService.hasPermission(activeRole, permission);
    }

    public boolean hasAllPermissions(Permission... permissions) {
        Role activeRole = getRole();
        if (activeRole == null || permissions == null) {
            return false;
        }
        return RolePermissionService.hasAllPermissions(activeRole, permissions);
    }

    public boolean hasAnyPermission(Permission... permissions) {
        Role activeRole = getRole();
        if (activeRole == null || permissions == null) {
            return false;
        }
        return RolePermissionService.hasAnyPermission(activeRole, permissions);
    }

    public boolean isAdmin() {
        return this.roles != null && this.roles.contains(Role.ADMIN);
    }

    public boolean isCaregiver() {
        return this.roles != null && this.roles.contains(Role.CAREGIVER);
    }

    public boolean isPatient() {
        return this.roles != null && this.roles.contains(Role.PATIENT);
    }

    public boolean isFamilyMember() {
        return this.roles != null && this.roles.contains(Role.FAMILY_MEMBER);
    }

    public boolean canModifyData() {
        Role activeRole = getRole();
        if (activeRole == null) {
            return false;
        }
        return activeRole.canModifyData();
    }

    public int getPermissionCount() {
        Role activeRole = getRole();
        if (activeRole == null) {
            return 0;
        }
        return RolePermissionService.getPermissionCount(activeRole);
    }

    // ========== Legacy Accessors & Boilerplate Compatibility ==========
    public boolean isActive() {
        return "ACTIVE".equalsIgnoreCase(status);
    }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
    public String getPasswordHash() { return passwordHash; }
    public void setPasswordHash(String passwordHash) { this.passwordHash = passwordHash; }
    
    public Long getId() { return id; }
    public String getName() { return name; }
    public String getEmail() { return email; }
    public Boolean getIsVerified() { return isVerified; }
    public String getVerificationToken() { return verificationToken; }
    public String getStatus() { return status; }
    public String getProfileImageUrl() { return profileImageUrl; }
    public String getPaymentCustomerId() { return paymentCustomerId; }
    public LocalDate getLastLoginDate() { return lastLoginDate; }
    public Integer getLoginStreak() { return loginStreak; }
    public Boolean getLeaderboardOptIn() { return leaderboardOptIn; }

    public void setId(Long id) { this.id = id; }
    public void setName(String name) { this.name = name; }
    public void setEmail(String email) { this.email = email; }
    public void setIsVerified(Boolean isVerified) { this.isVerified = isVerified; }
    public void setVerificationToken(String verificationToken) { this.verificationToken = verificationToken; }
    public void setStatus(String status) { this.status = status; }
    public void setProfileImageUrl(String profileImageUrl) { this.profileImageUrl = profileImageUrl; }
    public void setPaymentCustomerId(String paymentCustomerId) { this.paymentCustomerId = paymentCustomerId; }
    public void setLastLoginDate(LocalDate lastLoginDate) { this.lastLoginDate = lastLoginDate; }
    public void setLoginStreak(Integer loginStreak) { this.loginStreak = loginStreak; }
    public void setLeaderboardOptIn(Boolean leaderboardOptIn) { this.leaderboardOptIn = leaderboardOptIn; }

    public String getAddressLine1() { return addressLine1; }
    public String getAddressLine2() { return addressLine2; }
    public String getCity() { return city; }
    public String getState() { return state; }
    public String getPostalCode() { return postalCode; }
    public String getCountry() { return country; }
    public String getAddressPlaceId() { return addressPlaceId; }
    public String getAddressFormatted() { return addressFormatted; }
    public Double getAddressLatitude() { return addressLatitude; }
    public Double getAddressLongitude() { return addressLongitude; }

    public void setAddressLine1(String addressLine1) { this.addressLine1 = addressLine1; }
    public void setAddressLine2(String addressLine2) { this.addressLine2 = addressLine2; }
    public void setCity(String city) { this.city = city; }
    public void setState(String state) { this.state = state; }
    public void setPostalCode(String postalCode) { this.postalCode = postalCode; }
    public void setCountry(String country) { this.country = country; }
    public void setAddressPlaceId(String addressPlaceId) { this.addressPlaceId = addressPlaceId; }
    public void setAddressFormatted(String addressFormatted) { this.addressFormatted = addressFormatted; }
    public void setAddressLatitude(Double addressLatitude) { this.addressLatitude = addressLatitude; }
    public void setAddressLongitude(Double addressLongitude) { this.addressLongitude = addressLongitude; }
}