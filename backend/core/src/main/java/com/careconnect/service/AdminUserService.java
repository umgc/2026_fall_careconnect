package com.careconnect.service;

import com.careconnect.dto.AdminUserSummaryDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;

import java.util.Comparator;
import java.util.List;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/**
 * Admin-only user listing and role management.
 */
@Service
@RequiredArgsConstructor
public class AdminUserService {

    private final UserRepository userRepository;

    public List<AdminUserSummaryDTO> listUsers() {
        // Not paginated: admin-only endpoint and user count is bounded at team scale.
        // If user volume grows significantly, switch to Pageable.
        return userRepository.findAll().stream()
                .sorted(Comparator.comparing(User::getEmail, String.CASE_INSENSITIVE_ORDER))
                .map(this::toSummary)
                .toList();
    }

    public AdminUserSummaryDTO updateRole(
            final Long userId, final Role newRole, final User actingAdmin) {
        if (userId == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "User ID is required");
        }
        if (actingAdmin.getId() != null && actingAdmin.getId().equals(userId)) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Cannot change your own role");
        }

        final User target =
                userRepository
                        .findById(userId)
                        .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "User not found"));

        if (target.getRole() == Role.ADMIN && newRole != Role.ADMIN) {
            final long adminCount = userRepository.findByRole(Role.ADMIN).size();
            if (adminCount <= 1) {
                throw new AppException(HttpStatus.BAD_REQUEST, "Cannot demote the last admin");
            }
        }

        target.setRole(newRole);
        return toSummary(userRepository.save(target));
    }

    private AdminUserSummaryDTO toSummary(final User user) {
        return new AdminUserSummaryDTO(
                user.getId(),
                user.getName(),
                user.getEmail(),
                user.getRole().name(),
                Boolean.TRUE.equals(user.getIsVerified()),
                user.getLastLoginDate());
    }
}
