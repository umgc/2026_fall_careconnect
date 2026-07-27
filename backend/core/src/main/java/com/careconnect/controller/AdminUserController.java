package com.careconnect.controller;

import com.careconnect.dto.AdminUserSummaryDTO;
import com.careconnect.dto.UpdateUserRoleRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AdminUserService;
import com.careconnect.util.SecurityUtil;
import jakarta.validation.Valid;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Admin-only user listing and role updates. */
@RestController
@RequestMapping("/v1/api/admin/users")
@RequiredArgsConstructor
public class AdminUserController {

  private final SecurityUtil securityUtil;
  private final AuthorizationService authorizationService;
  private final AdminUserService adminUserService;

  /** Lists all users with safe summary fields only. */
  @GetMapping
  public List<AdminUserSummaryDTO> listUsers() throws UnauthorizedException {
    final User currentUser = securityUtil.resolveCurrentUser();
    authorizationService.requireAdmin(currentUser);
    return adminUserService.listUsers();
  }

  /** Updates a user's role (e.g. promote to ADMIN). */
  @PostMapping("/{userId}/role")
  public AdminUserSummaryDTO updateRole(
      @PathVariable final Long userId, @Valid @RequestBody final UpdateUserRoleRequest request)
      throws UnauthorizedException {
    final User currentUser = securityUtil.resolveCurrentUser();
    authorizationService.requireAdmin(currentUser);

    final Role role;
    try {
      role = Role.fromString(request.role());
    } catch (IllegalArgumentException ex) {
      throw new AppException(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    return adminUserService.updateRole(userId, role, currentUser);
  }
}
