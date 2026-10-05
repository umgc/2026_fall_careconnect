package com.careconnect.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for the Role enum.
 * Tests role definitions, conversions, and utility methods.
 */
public class RoleTest {

    @Test
    @DisplayName("Should have exactly 4 roles defined")
    public void testRoleCount() throws Exception {
        Role[] roles = Role.values();
        assertEquals(4, roles.length, "Should have exactly 4 roles defined");
    }

    @Test
    @DisplayName("All required roles should exist")
    public void testRequiredRolesExist() throws Exception {
        assertDoesNotThrow(() -> Role.valueOf("ADMIN"));
        assertDoesNotThrow(() -> Role.valueOf("CAREGIVER"));
        assertDoesNotThrow(() -> Role.valueOf("PATIENT"));
        assertDoesNotThrow(() -> Role.valueOf("FAMILY_MEMBER"));
    }

    @Test
    @DisplayName("All roles should have non-null display names")
    public void testAllRolesHaveDisplayNames() throws Exception {
        for (Role role : Role.values()) {
            assertNotNull(role.getDisplayName(),
                    "Role " + role.name() + " should have a display name");
            assertFalse(role.getDisplayName().isEmpty(),
                    "Role " + role.name() + " display name should not be empty");
        }
    }

    @Test
    @DisplayName("All roles should have non-null descriptions")
    public void testAllRolesHaveDescriptions() throws Exception {
        for (Role role : Role.values()) {
            assertNotNull(role.getDescription(),
                    "Role " + role.name() + " should have a description");
            assertFalse(role.getDescription().isEmpty(),
                    "Role " + role.name() + " description should not be empty");
        }
    }

    @Test
    @DisplayName("Display names should be user-friendly")
    public void testDisplayNamesAreUserFriendly() throws Exception {
        assertEquals("Administrator", Role.ADMIN.getDisplayName());
        assertEquals("Caregiver", Role.CAREGIVER.getDisplayName());
        assertEquals("Patient", Role.PATIENT.getDisplayName());
        assertEquals("Family Member", Role.FAMILY_MEMBER.getDisplayName());
    }

    @Test
    @DisplayName("fromString should handle uppercase input")
    public void testFromStringUppercase() throws Exception {
        assertEquals(Role.ADMIN, Role.fromString("ADMIN"));
        assertEquals(Role.CAREGIVER, Role.fromString("CAREGIVER"));
        assertEquals(Role.PATIENT, Role.fromString("PATIENT"));
        assertEquals(Role.FAMILY_MEMBER, Role.fromString("FAMILY_MEMBER"));
    }

    @Test
    @DisplayName("fromString should handle lowercase input")
    public void testFromStringLowercase() throws Exception {
        assertEquals(Role.ADMIN, Role.fromString("admin"));
        assertEquals(Role.CAREGIVER, Role.fromString("caregiver"));
        assertEquals(Role.PATIENT, Role.fromString("patient"));
        assertEquals(Role.FAMILY_MEMBER, Role.fromString("family_member"));
    }

    @Test
    @DisplayName("fromString should handle mixed case input")
    public void testFromStringMixedCase() throws Exception {
        assertEquals(Role.ADMIN, Role.fromString("Admin"));
        assertEquals(Role.CAREGIVER, Role.fromString("CareGiver"));
        assertEquals(Role.PATIENT, Role.fromString("PaTiEnT"));
    }

    @Test
    @DisplayName("fromString should handle space variations")
    public void testFromStringWithSpaces() throws Exception {
        assertEquals(Role.FAMILY_MEMBER, Role.fromString("family member"));
        assertEquals(Role.FAMILY_MEMBER, Role.fromString("FAMILY MEMBER"));
        assertEquals(Role.FAMILY_MEMBER, Role.fromString("Family Member"));
    }

    @Test
    @DisplayName("fromString should throw exception for null input")
    public void testFromStringNull() throws Exception {
        IllegalArgumentException exception = assertThrows(IllegalArgumentException.class, () -> {
            Role.fromString(null);
        });
        assertTrue(exception.getMessage().contains("cannot be null"),
                "Exception message should mention null");
    }

    @Test
    @DisplayName("fromString should throw exception for empty input")
    public void testFromStringEmpty() throws Exception {
        IllegalArgumentException exception = assertThrows(IllegalArgumentException.class, () -> {
            Role.fromString("");
        });
        assertTrue(exception.getMessage().contains("cannot be null or empty"),
                "Exception message should mention empty string");
    }

    @Test
    @DisplayName("fromString should throw exception for invalid role")
    public void testFromStringInvalid() throws Exception {
        IllegalArgumentException exception = assertThrows(IllegalArgumentException.class, () -> {
            Role.fromString("INVALID_ROLE");
        });
        assertTrue(exception.getMessage().contains("Invalid role"),
                "Exception message should mention invalid role");
        assertTrue(exception.getMessage().contains("ADMIN"),
                "Exception message should list valid roles");
    }

    @Test
    @DisplayName("toApiString should return lowercase with underscores")
    public void testToApiString() throws Exception {
        assertEquals("admin", Role.ADMIN.toApiString());
        assertEquals("caregiver", Role.CAREGIVER.toApiString());
        assertEquals("patient", Role.PATIENT.toApiString());
        assertEquals("family_member", Role.FAMILY_MEMBER.toApiString());
    }

    @Test
    @DisplayName("isAdmin should return true only for Admin role")
    public void testIsAdmin() throws Exception {
        assertTrue(Role.ADMIN.isAdmin());
        assertFalse(Role.CAREGIVER.isAdmin());
        assertFalse(Role.PATIENT.isAdmin());
        assertFalse(Role.FAMILY_MEMBER.isAdmin());
    }

    @Test
    @DisplayName("isCaregiver should return true only for Caregiver role")
    public void testIsCaregiver() throws Exception {
        assertFalse(Role.ADMIN.isCaregiver());
        assertTrue(Role.CAREGIVER.isCaregiver());
        assertFalse(Role.PATIENT.isCaregiver());
        assertFalse(Role.FAMILY_MEMBER.isCaregiver());
    }

    @Test
    @DisplayName("isPatient should return true only for Patient role")
    public void testIsPatient() throws Exception {
        assertFalse(Role.ADMIN.isPatient());
        assertFalse(Role.CAREGIVER.isPatient());
        assertTrue(Role.PATIENT.isPatient());
        assertFalse(Role.FAMILY_MEMBER.isPatient());
    }

    @Test
    @DisplayName("isFamilyMember should return true only for Family Member role")
    public void testIsFamilyMember() throws Exception {
        assertFalse(Role.ADMIN.isFamilyMember());
        assertFalse(Role.CAREGIVER.isFamilyMember());
        assertFalse(Role.PATIENT.isFamilyMember());
        assertTrue(Role.FAMILY_MEMBER.isFamilyMember());
    }

    @Test
    @DisplayName("canModifyData should return false only for Family Member")
    public void testCanModifyData() throws Exception {
        assertTrue(Role.ADMIN.canModifyData(),
                "Admin should be able to modify data");
        assertTrue(Role.CAREGIVER.canModifyData(),
                "Caregiver should be able to modify data");
        assertTrue(Role.PATIENT.canModifyData(),
                "Patient should be able to modify own data");
        assertFalse(Role.FAMILY_MEMBER.canModifyData(),
                "Family Member should be read-only");
    }

    @Test
    @DisplayName("getHierarchyLevel should return correct levels")
    public void testGetHierarchyLevel() throws Exception {
        assertEquals(0, Role.ADMIN.getHierarchyLevel(),
                "Admin should be level 0 (highest)");
        assertEquals(1, Role.CAREGIVER.getHierarchyLevel(),
                "Caregiver should be level 1");
        assertEquals(2, Role.PATIENT.getHierarchyLevel(),
                "Patient should be level 2");
        assertEquals(3, Role.FAMILY_MEMBER.getHierarchyLevel(),
                "Family Member should be level 3 (lowest)");
    }

    @Test
    @DisplayName("Hierarchy levels should be unique")
    public void testHierarchyLevelsAreUnique() throws Exception {
        Role[] roles = Role.values();
        for (int i = 0; i < roles.length; i++) {
            for (int j = i + 1; j < roles.length; j++) {
                assertNotEquals(roles[i].getHierarchyLevel(), roles[j].getHierarchyLevel(),
                        "Each role should have a unique hierarchy level");
            }
        }
    }

    @Test
    @DisplayName("hasHigherOrEqualAuthorityThan should work correctly")
    public void testHasHigherOrEqualAuthorityThan() throws Exception {
        // Admin has higher authority than everyone
        assertTrue(Role.ADMIN.hasHigherOrEqualAuthorityThan(Role.ADMIN));
        assertTrue(Role.ADMIN.hasHigherOrEqualAuthorityThan(Role.CAREGIVER));
        assertTrue(Role.ADMIN.hasHigherOrEqualAuthorityThan(Role.PATIENT));
        assertTrue(Role.ADMIN.hasHigherOrEqualAuthorityThan(Role.FAMILY_MEMBER));

        // Caregiver has higher authority than Patient and Family
        assertFalse(Role.CAREGIVER.hasHigherOrEqualAuthorityThan(Role.ADMIN));
        assertTrue(Role.CAREGIVER.hasHigherOrEqualAuthorityThan(Role.CAREGIVER));
        assertTrue(Role.CAREGIVER.hasHigherOrEqualAuthorityThan(Role.PATIENT));
        assertTrue(Role.CAREGIVER.hasHigherOrEqualAuthorityThan(Role.FAMILY_MEMBER));

        // Patient has higher authority than Family only
        assertFalse(Role.PATIENT.hasHigherOrEqualAuthorityThan(Role.ADMIN));
        assertFalse(Role.PATIENT.hasHigherOrEqualAuthorityThan(Role.CAREGIVER));
        assertTrue(Role.PATIENT.hasHigherOrEqualAuthorityThan(Role.PATIENT));
        assertTrue(Role.PATIENT.hasHigherOrEqualAuthorityThan(Role.FAMILY_MEMBER));

        // Family Member has lowest authority
        assertFalse(Role.FAMILY_MEMBER.hasHigherOrEqualAuthorityThan(Role.ADMIN));
        assertFalse(Role.FAMILY_MEMBER.hasHigherOrEqualAuthorityThan(Role.CAREGIVER));
        assertFalse(Role.FAMILY_MEMBER.hasHigherOrEqualAuthorityThan(Role.PATIENT));
        assertTrue(Role.FAMILY_MEMBER.hasHigherOrEqualAuthorityThan(Role.FAMILY_MEMBER));
    }

    @Test
    @DisplayName("toString should include role name, display name, and description")
    public void testToString() throws Exception {
        String adminString = Role.ADMIN.toString();
        assertTrue(adminString.contains("ADMIN"),
                "toString should contain role name");
        assertTrue(adminString.contains("Administrator"),
                "toString should contain display name");
        assertTrue(adminString.contains("Full system access"),
                "toString should contain description");
    }

    @Test
    @DisplayName("Role.values() should return all roles")
    public void testValuesMethod() throws Exception {
        Role[] roles = Role.values();
        assertNotNull(roles, "values() should not return null");
        assertEquals(4, roles.length, "values() should return 4 roles");
    }

    @Test
    @DisplayName("Role.valueOf() should work with valid role names")
    public void testValueOfMethod() throws Exception {
        Role role = Role.valueOf("ADMIN");
        assertEquals(Role.ADMIN, role, "valueOf should return correct role");
    }

    @Test
    @DisplayName("Role.valueOf() should throw exception for invalid names")
    public void testValueOfInvalidName() throws Exception {
        assertThrows(IllegalArgumentException.class, () -> {
            Role.valueOf("INVALID_ROLE");
        }, "valueOf should throw exception for invalid role name");
    }

    @Test
    @DisplayName("Roles should have unique names")
    public void testRolesHaveUniqueNames() throws Exception {
        Role[] roles = Role.values();
        for (int i = 0; i < roles.length; i++) {
            for (int j = i + 1; j < roles.length; j++) {
                assertNotEquals(roles[i].name(), roles[j].name(),
                        "Roles should have unique names");
            }
        }
    }

    @Test
    @DisplayName("Role descriptions should be meaningful")
    public void testRoleDescriptionsAreMeaningful() throws Exception {
        for (Role role : Role.values()) {
            String description = role.getDescription();
            assertTrue(description.length() >= 10,
                    "Role " + role.name() + " description should be meaningful (at least 10 chars)");
            assertTrue(Character.isUpperCase(description.charAt(0)),
                    "Role " + role.name() + " description should start with capital letter");
        }
    }

    @Test
    @DisplayName("fromString and toApiString should be reversible")
    public void testFromStringAndToApiStringReversible() throws Exception {
        for (Role role : Role.values()) {
            String apiString = role.toApiString();
            Role converted = Role.fromString(apiString);
            assertEquals(role, converted,
                    "Converting to API string and back should return same role");
        }
    }
}