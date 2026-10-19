package com.careconnect.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.AdminUserSummaryDTO;
import com.careconnect.dto.UpdateUserRoleRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AdminUserService;
import com.careconnect.util.SecurityUtil;

import java.time.LocalDate;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AdminUserControllerTest {

    private final User adminUser = buildUser(Role.ADMIN);
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @Mock
    private AdminUserService adminUserService;
    @InjectMocks
    private AdminUserController controller;

    private static AdminUserSummaryDTO sampleSummary() {
        return new AdminUserSummaryDTO(
                2L, "Jane Doe", "jane@example.com", "CAREGIVER", true, LocalDate.of(2026, 7, 1));
    }

    private static User buildUser(final Role role) {
        final User user = new User();
        user.setId(1L);
        user.setEmail("admin@test.com");
        user.setRole(role);
        return user;
    }

    @Test
    void listUsers_asAdmin_returnsSummaries() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(adminUserService.listUsers()).thenReturn(List.of(sampleSummary()));

        final List<AdminUserSummaryDTO> response = controller.listUsers();

        assertThat(response).hasSize(1);
        assertThat(response.get(0).email()).isEqualTo("jane@example.com");
        verify(authorizationService).requireAdmin(adminUser);
        verify(adminUserService).listUsers();
    }

    @Test
    void listUsers_whenNotAdmin_propagatesUnauthorized() throws Exception {
        final User caregiver = buildUser(Role.CAREGIVER);
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        doThrow(new UnauthorizedException("Admin access required"))
                .when(authorizationService)
                .requireAdmin(caregiver);

        org.junit.jupiter.api.Assertions.assertThrows(
                UnauthorizedException.class, () -> controller.listUsers());
    }

    @Test
    void updateRole_asAdmin_promotesUser() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(adminUserService.updateRole(2L, Role.ADMIN, adminUser))
                .thenReturn(
                        new AdminUserSummaryDTO(
                                2L, "Jane Doe", "jane@example.com", "ADMIN", true, LocalDate.of(2026, 7, 1)));

        final AdminUserSummaryDTO response =
                controller.updateRole(2L, new UpdateUserRoleRequest("ADMIN"));

        assertThat(response.role()).isEqualTo("ADMIN");
        verify(authorizationService).requireAdmin(adminUser);
        verify(adminUserService).updateRole(2L, Role.ADMIN, adminUser);
    }

    @Test
    void updateRole_withInvalidRole_throwsBadRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);

        org.junit.jupiter.api.Assertions.assertThrows(
                AppException.class,
                () -> controller.updateRole(2L, new UpdateUserRoleRequest("INVALID")));
    }

    @Test
    void updateRole_whenNotAdmin_propagatesUnauthorized() throws Exception {
        final User caregiver = buildUser(Role.CAREGIVER);
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        doThrow(new UnauthorizedException("Admin access required"))
                .when(authorizationService)
                .requireAdmin(caregiver);

        org.junit.jupiter.api.Assertions.assertThrows(
                UnauthorizedException.class,
                () -> controller.updateRole(2L, new UpdateUserRoleRequest("ADMIN")));
    }
}
