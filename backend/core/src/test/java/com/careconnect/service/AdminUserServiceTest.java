package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.AdminUserSummaryDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

@ExtendWith(MockitoExtension.class)
class AdminUserServiceTest {

  @Mock private UserRepository userRepository;

  @InjectMocks private AdminUserService adminUserService;

  @Test
  void listUsers_returnsSortedSummariesWithoutSecrets() {
    final User userA = buildUser(2L, "b@example.com", Role.CAREGIVER);
    final User userB = buildUser(3L, "a@example.com", Role.PATIENT);
    when(userRepository.findAll()).thenReturn(List.of(userA, userB));

    final List<AdminUserSummaryDTO> result = adminUserService.listUsers();

    assertThat(result).hasSize(2);
    assertThat(result.get(0).email()).isEqualTo("a@example.com");
    assertThat(result.get(1).email()).isEqualTo("b@example.com");
    assertThat(result.get(0).role()).isEqualTo("PATIENT");
  }

  @Test
  void updateRole_promotesUserToAdmin() {
    final User actingAdmin = buildUser(1L, "admin@test.com", Role.ADMIN);
    final User target = buildUser(2L, "jane@example.com", Role.CAREGIVER);
    when(userRepository.findById(2L)).thenReturn(Optional.of(target));
    when(userRepository.save(target)).thenAnswer(invocation -> invocation.getArgument(0));

    final AdminUserSummaryDTO result =
        adminUserService.updateRole(2L, Role.ADMIN, actingAdmin);

    assertThat(result.role()).isEqualTo("ADMIN");
    assertThat(target.getRole()).isEqualTo(Role.ADMIN);
    verify(userRepository).save(target);
  }

  @Test
  void updateRole_whenUserMissing_throwsNotFound() {
    final User actingAdmin = buildUser(1L, "admin@test.com", Role.ADMIN);
    when(userRepository.findById(99L)).thenReturn(Optional.empty());

    final AppException ex =
        assertThrows(
            AppException.class,
            () -> adminUserService.updateRole(99L, Role.ADMIN, actingAdmin));

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void updateRole_whenChangingOwnRole_throwsBadRequest() {
    final User actingAdmin = buildUser(1L, "admin@test.com", Role.ADMIN);

    final AppException ex =
        assertThrows(
            AppException.class,
            () -> adminUserService.updateRole(1L, Role.CAREGIVER, actingAdmin));

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(ex.getMessage()).contains("own role");
  }

  @Test
  void updateRole_whenDemotingLastAdmin_throwsBadRequest() {
    final User actingAdmin = buildUser(1L, "admin@test.com", Role.ADMIN);
    final User onlyAdmin = buildUser(2L, "solo@example.com", Role.ADMIN);
    when(userRepository.findById(2L)).thenReturn(Optional.of(onlyAdmin));
    when(userRepository.findByRole(Role.ADMIN)).thenReturn(List.of(onlyAdmin));

    final AppException ex =
        assertThrows(
            AppException.class,
            () -> adminUserService.updateRole(2L, Role.CAREGIVER, actingAdmin));

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(ex.getMessage()).contains("last admin");
  }

  @Test
  void updateRole_persistsNewRole() {
    final User actingAdmin = buildUser(1L, "admin@test.com", Role.ADMIN);
    final User target = buildUser(2L, "jane@example.com", Role.CAREGIVER);
    when(userRepository.findById(2L)).thenReturn(Optional.of(target));
    when(userRepository.save(target)).thenAnswer(invocation -> invocation.getArgument(0));

    adminUserService.updateRole(2L, Role.ADMIN, actingAdmin);

    final ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
    verify(userRepository).save(captor.capture());
    assertThat(captor.getValue().getRole()).isEqualTo(Role.ADMIN);
  }

  private static User buildUser(final Long id, final String email, final Role role) {
    final User user = new User();
    user.setId(id);
    user.setName("User " + id);
    user.setEmail(email);
    user.setRole(role);
    user.setIsVerified(true);
    user.setLastLoginDate(LocalDate.of(2026, 7, 1));
    user.setPassword("secret");
    return user;
  }
}
