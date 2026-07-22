package com.careconnect.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for the Permission enum.
 * Tests permission definitions, descriptions, and utility methods.
 */
public class PermissionTest {

    @Test
    @DisplayName("All permissions should have non-null descriptions")
    public void testAllPermissionsHaveDescriptions() throws Exception {
        for (Permission permission : Permission.values()) {
            assertNotNull(permission.getDescription(), 
                "Permission " + permission.name() + " should have a description");
            assertFalse(permission.getDescription().isEmpty(),
                "Permission " + permission.name() + " description should not be empty");
        }
    }

    @Test
    @DisplayName("Should have exactly 29 permissions defined")
    public void testPermissionCount() throws Exception {
        Permission[] permissions = Permission.values();
        assertEquals(29, permissions.length, 
            "Should have exactly 29 permissions defined");
    }

    @Test
    @DisplayName("Permission names should be in UPPER_SNAKE_CASE format")
    public void testPermissionNamingConvention() throws Exception {
        for (Permission permission : Permission.values()) {
            String name = permission.name();
            assertTrue(name.equals(name.toUpperCase()),
                "Permission " + name + " should be uppercase");
            assertTrue(name.matches("[A-Z_]+"),
                "Permission " + name + " should only contain uppercase letters and underscores");
        }
    }

    @Test
    @DisplayName("Key user management permissions should exist")
    public void testUserManagementPermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_ALL_USERS"));
        assertDoesNotThrow(() -> Permission.valueOf("MANAGE_USERS"));
        assertDoesNotThrow(() -> Permission.valueOf("ASSIGN_ROLES"));
    }

    @Test
    @DisplayName("Key patient management permissions should exist")
    public void testPatientManagementPermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_ALL_PATIENTS"));
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_ASSIGNED_PATIENTS"));
        assertDoesNotThrow(() -> Permission.valueOf("CREATE_PATIENTS"));
        assertDoesNotThrow(() -> Permission.valueOf("UPDATE_PATIENTS"));
        assertDoesNotThrow(() -> Permission.valueOf("DELETE_PATIENTS"));
    }

    @Test
    @DisplayName("Key task management permissions should exist")
    public void testTaskManagementPermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("CREATE_TASKS"));
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_TASKS"));
        assertDoesNotThrow(() -> Permission.valueOf("UPDATE_TASKS"));
        assertDoesNotThrow(() -> Permission.valueOf("DELETE_TASKS"));
        assertDoesNotThrow(() -> Permission.valueOf("COMPLETE_TASKS"));
    }

    @Test
    @DisplayName("Key health data permissions should exist")
    public void testHealthDataPermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_HEALTH_DATA"));
        assertDoesNotThrow(() -> Permission.valueOf("RECORD_HEALTH_DATA"));
        assertDoesNotThrow(() -> Permission.valueOf("EXPORT_HEALTH_DATA"));
    }

    @Test
    @DisplayName("Billing permissions should exist")
    public void testBillingPermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_BILLING"));
        assertDoesNotThrow(() -> Permission.valueOf("MANAGE_SUBSCRIPTIONS"));
    }

    @Test
    @DisplayName("Communication permissions should exist")
    public void testCommunicationPermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("SEND_MESSAGES"));
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_MESSAGES"));
    }

    @Test
    @DisplayName("Analytics permissions should exist")
    public void testAnalyticsPermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_ANALYTICS"));
        assertDoesNotThrow(() -> Permission.valueOf("EXPORT_REPORTS"));
    }

    @Test
    @DisplayName("AI and device permissions should exist")
    public void testAIAndDevicePermissionsExist() throws Exception {
        assertDoesNotThrow(() -> Permission.valueOf("USE_AI_FEATURES"));
        assertDoesNotThrow(() -> Permission.valueOf("REVIEW_AI_HOLDS"));
        assertDoesNotThrow(() -> Permission.valueOf("MANAGE_DEVICES"));
    }

    @Test
    @DisplayName("isAdminOnly should correctly identify admin-only permissions")
    public void testIsAdminOnly() throws Exception {
        // These should be admin-only
        assertTrue(Permission.VIEW_ALL_USERS.isAdminOnly(),
            "VIEW_ALL_USERS should be admin-only");
        assertTrue(Permission.MANAGE_USERS.isAdminOnly(),
            "MANAGE_USERS should be admin-only");
        assertTrue(Permission.ASSIGN_ROLES.isAdminOnly(),
            "ASSIGN_ROLES should be admin-only");
        assertTrue(Permission.VIEW_ALL_PATIENTS.isAdminOnly(),
            "VIEW_ALL_PATIENTS should be admin-only");
        assertTrue(Permission.DELETE_PATIENTS.isAdminOnly(),
            "DELETE_PATIENTS should be admin-only");

        // These should NOT be admin-only
        assertFalse(Permission.CREATE_TASKS.isAdminOnly(),
            "CREATE_TASKS should not be admin-only");
        assertFalse(Permission.VIEW_HEALTH_DATA.isAdminOnly(),
            "VIEW_HEALTH_DATA should not be admin-only");
        assertFalse(Permission.SEND_MESSAGES.isAdminOnly(),
            "SEND_MESSAGES should not be admin-only");
    }

    @Test
    @DisplayName("getDisplayName should return properly formatted names")
    public void testGetDisplayName() throws Exception {
        assertEquals("Create Tasks", Permission.CREATE_TASKS.getDisplayName(),
            "Display name should be formatted with spaces and proper case");
        assertEquals("View Health Data", Permission.VIEW_HEALTH_DATA.getDisplayName(),
            "Display name should be formatted with spaces and proper case");
        assertEquals("Manage Users", Permission.MANAGE_USERS.getDisplayName(),
            "Display name should be formatted with spaces and proper case");
    }

    @Test
    @DisplayName("toString should include permission name and description")
    public void testToString() throws Exception {
        String result = Permission.CREATE_TASKS.toString();
        assertTrue(result.contains("CREATE_TASKS"),
            "toString should contain permission name");
        assertTrue(result.contains("Create tasks for patients"),
            "toString should contain description");
    }

    @Test
    @DisplayName("Permission.values() should return all permissions")
    public void testValuesMethod() throws Exception {
        Permission[] permissions = Permission.values();
        assertNotNull(permissions, "values() should not return null");
        assertTrue(permissions.length > 0, "values() should return at least one permission");
        assertEquals(29, permissions.length, "Should return all 29 permissions");
    }

    @Test
    @DisplayName("Permission.valueOf() should work with valid permission names")
    public void testValueOfMethod() throws Exception {
        Permission permission = Permission.valueOf("CREATE_TASKS");
        assertEquals(Permission.CREATE_TASKS, permission,
            "valueOf should return correct permission");
    }

    @Test
    @DisplayName("Permission.valueOf() should throw exception for invalid names")
    public void testValueOfInvalidName() throws Exception {
        assertThrows(IllegalArgumentException.class, () -> {
            Permission.valueOf("INVALID_PERMISSION");
        }, "valueOf should throw exception for invalid permission name");
    }

    @Test
    @DisplayName("Permissions should have unique names")
    public void testPermissionsHaveUniqueNames() throws Exception {
        Permission[] permissions = Permission.values();
        for (int i = 0; i < permissions.length; i++) {
            for (int j = i + 1; j < permissions.length; j++) {
                assertNotEquals(permissions[i].name(), permissions[j].name(),
                    "Permissions should have unique names");
            }
        }
    }

    @Test
    @DisplayName("Critical permissions for HIPAA compliance should exist")
    public void testHIPAACompliancePermissions() throws Exception {
        // These are critical for HIPAA compliance
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_HEALTH_DATA"));
        assertDoesNotThrow(() -> Permission.valueOf("RECORD_HEALTH_DATA"));
        assertDoesNotThrow(() -> Permission.valueOf("EXPORT_HEALTH_DATA"));
        assertDoesNotThrow(() -> Permission.valueOf("DELETE_PATIENTS"));
        assertDoesNotThrow(() -> Permission.valueOf("VIEW_ALL_PATIENTS"));
    }

    @Test
    @DisplayName("All permission descriptions should be meaningful")
    public void testPermissionDescriptionsAreMeaningful() throws Exception {
        for (Permission permission : Permission.values()) {
            String description = permission.getDescription();
            // Description should be at least 10 characters
            assertTrue(description.length() >= 10,
                "Permission " + permission.name() + " description should be meaningful (at least 10 chars)");
            // Description should start with a capital letter
            assertTrue(Character.isUpperCase(description.charAt(0)),
                "Permission " + permission.name() + " description should start with capital letter");
        }
    }

    @Test
    @DisplayName("Permission enum should be ordered logically by category")
    public void testPermissionOrdering() throws Exception {
        Permission[] permissions = Permission.values();
        
        // User management permissions should come first (indices 0-2)
        assertEquals("VIEW_ALL_USERS", permissions[0].name());
        assertEquals("MANAGE_USERS", permissions[1].name());
        assertEquals("ASSIGN_ROLES", permissions[2].name());
        
        // Patient management permissions should follow (indices 3-7)
        assertEquals("VIEW_ALL_PATIENTS", permissions[3].name());
        assertEquals("VIEW_ASSIGNED_PATIENTS", permissions[4].name());
        assertEquals("CREATE_PATIENTS", permissions[5].name());
    }
}