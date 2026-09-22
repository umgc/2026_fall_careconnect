package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.Builder;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.Set;

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

    // Split name into first and last name for better usability

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

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    @Builder.Default
    @Column(name = "email_verified", nullable = false)
    private Boolean isVerified = false;

    private String verificationToken;

    @Column(name = "payment_customer_id")
    private String paymentCustomerId;

    // Billing address fields (geocoded + standardized)
    @Column(name = "address_line1")
    private String addressLine1;

    @Column(name = "address_line2")
    private String addressLine2;

    @Column(name = "city")
    private String city;

    @Column(name = "state", length = 2)
    private String state; // 2-letter state code (e.g., "CA", "NY")

    @Column(name = "postal_code")
    private String postalCode;

    @Column(name = "country", length = 2)
    private String country; // 2-letter country code (default "US")

    @Column(name = "address_place_id")
    private String addressPlaceId; // Google Places place_id or equivalent provider ID

    @Column(name = "address_formatted")
    private String addressFormatted; // Full formatted address string from provider

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

    // ========== RBAC Permission Methods ==========

    /**
     * Get all permissions for this user based on their role.
     *
     * @return Set of permissions assigned to the user's role
     * @example User caregiver = getCurrentUser();
     * Set<Permission> permissions = caregiver.getPermissions();
     * // Returns 18 permissions for caregiver
     */
    public Set<Permission> getPermissions() {
        if (this.role == null) {
            return Set.of(); // Return empty set if no role assigned
        }
        return RolePermissionService.getPermissionsForRole(this.role);
    }

    /**
     * Check if user has a specific permission.
     *
     * @param permission The permission to check
     * @return true if user has the permission, false otherwise
     * @example if (user.hasPermission(Permission.CREATE_TASKS)) {
     * // User can create tasks
     * }
     */
    public boolean hasPermission(Permission permission) {
        if (this.role == null || permission == null) {
            return false;
        }
        return RolePermissionService.hasPermission(this.role, permission);
    }

    /**
     * Check if user has ALL of the specified permissions.
     *
     * @param permissions One or more permissions to check
     * @return true if user has ALL permissions, false otherwise
     * @example if (user.hasAllPermissions(Permission.CREATE_TASKS, Permission.VIEW_HEALTH_DATA)) {
     * // User has both permissions
     * }
     */
    public boolean hasAllPermissions(Permission... permissions) {
        if (this.role == null || permissions == null) {
            return false;
        }
        return RolePermissionService.hasAllPermissions(this.role, permissions);
    }

    /**
     * Check if user has ANY of the specified permissions.
     *
     * @param permissions One or more permissions to check
     * @return true if user has at least ONE permission, false otherwise
     * @example if (user.hasAnyPermission(Permission.CREATE_TASKS, Permission.UPDATE_TASKS)) {
     * // User has at least one of these permissions
     * }
     */
    public boolean hasAnyPermission(Permission... permissions) {
        if (this.role == null || permissions == null) {
            return false;
        }
        return RolePermissionService.hasAnyPermission(this.role, permissions);
    }

    /**
     * Check if user is an administrator.
     * Convenience method for common role check.
     *
     * @return true if user has Admin role
     * @example if (user.isAdmin()) {
     * // Show admin menu
     * }
     */
    public boolean isAdmin() {
        return this.role == Role.ADMIN;
    }

    /**
     * Check if user is a caregiver.
     *
     * @return true if user has Caregiver role
     */
    public boolean isCaregiver() {
        return this.role == Role.CAREGIVER;
    }

    /**
     * Check if user is a patient.
     *
     * @return true if user has Patient role
     */
    public boolean isPatient() {
        return this.role == Role.PATIENT;
    }

    /**
     * Check if user is a family member.
     *
     * @return true if user has Family Member role
     */
    public boolean isFamilyMember() {
        return this.role == Role.FAMILY_MEMBER;
    }

    /**
     * Check if user can modify data (not read-only).
     * Family members have read-only access.
     *
     * @return true if user can create/update/delete data
     */
    public boolean canModifyData() {
        if (this.role == null) {
            return false;
        }
        return this.role.canModifyData();
    }

    /**
     * Get count of permissions this user has.
     * Useful for displaying permission summaries.
     *
     * @return Number of permissions
     */
    public int getPermissionCount() {
        if (this.role == null) {
            return 0;
        }
        return RolePermissionService.getPermissionCount(this.role);
    }

    // ========== Existing Methods ==========
    public boolean isActive() {
        return "ACTIVE".equalsIgnoreCase(status);
    }

    // Explicit getter and setter methods for password fields
    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public void setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
    }

    // Additional getters for compatibility
    public Long getId() {
        return id;
    }

    // Additional setters for compatibility
    public void setId(Long id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public Role getRole() {
        return role;
    }

    public void setRole(Role role) {
        this.role = role;
    }

    public Boolean getIsVerified() {
        return isVerified;
    }

    public void setIsVerified(Boolean isVerified) {
        this.isVerified = isVerified;
    }

    public String getVerificationToken() {
        return verificationToken;
    }

    public void setVerificationToken(String verificationToken) {
        this.verificationToken = verificationToken;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getProfileImageUrl() {
        return profileImageUrl;
    }

    public void setProfileImageUrl(String profileImageUrl) {
        this.profileImageUrl = profileImageUrl;
    }

    public String getPaymentCustomerId() {
        return paymentCustomerId;
    }

    public void setPaymentCustomerId(String paymentCustomerId) {
        this.paymentCustomerId = paymentCustomerId;
    }

    public LocalDate getLastLoginDate() {
        return lastLoginDate;
    }

    public void setLastLoginDate(LocalDate lastLoginDate) {
        this.lastLoginDate = lastLoginDate;
    }

    public Integer getLoginStreak() {
        return loginStreak;
    }

    public void setLoginStreak(Integer loginStreak) {
        this.loginStreak = loginStreak;
    }

    public Boolean getLeaderboardOptIn() {
        return leaderboardOptIn;
    }

    public void setLeaderboardOptIn(Boolean leaderboardOptIn) {
        this.leaderboardOptIn = leaderboardOptIn;
    }

    // Address getters
    public String getAddressLine1() {
        return addressLine1;
    }

    // Address setters
    public void setAddressLine1(String addressLine1) {
        this.addressLine1 = addressLine1;
    }

    public String getAddressLine2() {
        return addressLine2;
    }

    public void setAddressLine2(String addressLine2) {
        this.addressLine2 = addressLine2;
    }

    public String getCity() {
        return city;
    }

    public void setCity(String city) {
        this.city = city;
    }

    public String getState() {
        return state;
    }

    public void setState(String state) {
        this.state = state;
    }

    public String getPostalCode() {
        return postalCode;
    }

    public void setPostalCode(String postalCode) {
        this.postalCode = postalCode;
    }

    public String getCountry() {
        return country;
    }

    public void setCountry(String country) {
        this.country = country;
    }

    public String getAddressPlaceId() {
        return addressPlaceId;
    }

    public void setAddressPlaceId(String addressPlaceId) {
        this.addressPlaceId = addressPlaceId;
    }

    public String getAddressFormatted() {
        return addressFormatted;
    }

    public void setAddressFormatted(String addressFormatted) {
        this.addressFormatted = addressFormatted;
    }

    public Double getAddressLatitude() {
        return addressLatitude;
    }

    public void setAddressLatitude(Double addressLatitude) {
        this.addressLatitude = addressLatitude;
    }

    public Double getAddressLongitude() {
        return addressLongitude;
    }

    public void setAddressLongitude(Double addressLongitude) {
        this.addressLongitude = addressLongitude;
    }
}
