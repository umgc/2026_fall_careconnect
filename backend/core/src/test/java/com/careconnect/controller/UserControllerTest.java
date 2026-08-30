package com.careconnect.controller;

import com.careconnect.dto.LeaderboardEntry;
import com.careconnect.dto.ResetPasswordRequest;
import com.careconnect.dto.SetupPasswordRequest;
import com.careconnect.dto.UserResponse;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.UserPasswordService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class UserControllerTest {

    @Mock
    private UserPasswordService userPasswordService;

    @Mock
    private UserRepository userRepo;

    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private UserController controller;

    // ─── resetPassword ────────────────────────────────────────────────────────

    @Test
    void resetPassword_success_returnsOkWithMessage() throws Exception {
        final ResetPasswordRequest req = new ResetPasswordRequest();
        req.setUsername("user@test.com");
        req.setResetToken("token123");
        req.setNewPassword("NewPass1!");
        doNothing().when(userPasswordService).resetPasswordWithToken("user@test.com", "token123", "NewPass1!");

        final ResponseEntity<?> response = controller.resetPassword(req);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body).containsEntry("message", "Password updated successfully");
    }

    @Test
    void resetPassword_exception_returnsBadRequest() throws Exception {
        final ResetPasswordRequest req = new ResetPasswordRequest();
        req.setUsername("bad@test.com");
        req.setResetToken("bad-token");
        req.setNewPassword("pass");
        doThrow(new RuntimeException("Invalid token"))
                .when(userPasswordService).resetPasswordWithToken("bad@test.com", "bad-token", "pass");

        final ResponseEntity<?> response = controller.resetPassword(req);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked") final Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body).containsEntry("error", "Invalid token");
    }

    // ─── setupPassword ────────────────────────────────────────────────────────

    @Test
    void setupPassword_success_returnsOkWithMessage() throws Exception {
        final SetupPasswordRequest req = new SetupPasswordRequest("p@test.com", "verify-token", "MyPass1!");
        doNothing().when(userPasswordService).setupPasswordWithVerificationToken("p@test.com", "verify-token", "MyPass1!");

        final ResponseEntity<?> response = controller.setupPassword(req);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body).containsEntry("message", "Password setup completed successfully");
    }

    @Test
    void setupPassword_exception_returnsBadRequest() throws Exception {
        final SetupPasswordRequest req = new SetupPasswordRequest("p@test.com", "bad-token", "pass");
        doThrow(new RuntimeException("Expired token"))
                .when(userPasswordService).setupPasswordWithVerificationToken("p@test.com", "bad-token", "pass");

        final ResponseEntity<?> response = controller.setupPassword(req);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked") final Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body).containsEntry("error", "Expired token");
    }

    // ─── searchUsers ──────────────────────────────────────────────────────────

    @Test
    void searchUsers_currentUserNotFound_returnsBadRequest() throws Exception {
        when(userRepo.findByNameContainingIgnoreCaseOrEmailContainingIgnoreCase("alice", "alice"))
                .thenReturn(List.of());
        when(userRepo.findById(99L)).thenReturn(Optional.empty());

        final ResponseEntity<List<UserResponse>> response = controller.searchUsers("alice", 99L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    void searchUsers_excludesSelfAndReturnsList() throws Exception {
        final User self = User.builder().id(1L).name("Alice").email("alice@test.com")
                .role(Role.PATIENT).password("p").status("ACTIVE").build();
        final User other = User.builder().id(2L).name("Bob").email("bob@test.com")
                .role(Role.CAREGIVER).password("p").status("ACTIVE").build();

        when(userRepo.findByNameContainingIgnoreCaseOrEmailContainingIgnoreCase("alice", "alice"))
                .thenReturn(List.of(self, other));
        when(userRepo.findById(1L)).thenReturn(Optional.of(self));

        final ResponseEntity<List<UserResponse>> response = controller.searchUsers("alice", 1L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        // self (same ID + email + role) should be filtered out; only 'other' remains
        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getEmail()).isEqualTo("bob@test.com");
    }

    @Test
    void searchUsers_noMatchesSelf_returnsAllResults() throws Exception {
        final User currentUser = User.builder().id(1L).name("Alice").email("alice@test.com")
                .role(Role.PATIENT).password("p").status("ACTIVE").build();
        final User other = User.builder().id(2L).name("Bob").email("bob@test.com")
                .role(Role.CAREGIVER).password("p").status("ACTIVE").build();

        when(userRepo.findByNameContainingIgnoreCaseOrEmailContainingIgnoreCase("bob", "bob"))
                .thenReturn(List.of(other));
        when(userRepo.findById(1L)).thenReturn(Optional.of(currentUser));

        final ResponseEntity<List<UserResponse>> response = controller.searchUsers("bob", 1L);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
    }

    // ─── toggleLeaderboardOptIn ───────────────────────────────────────────────

    @Test
    void toggleLeaderboardOptIn_missingOptIn_returnsBadRequest() throws Exception {
        final ResponseEntity<?> response = controller.toggleLeaderboardOptIn(1L, Collections.emptyMap());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked") final Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body).containsKey("error");
    }

    @Test
    void toggleLeaderboardOptIn_userNotFound_returnsNotFound() throws Exception {
        when(userRepo.findById(99L)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.toggleLeaderboardOptIn(99L, Map.of("optIn", true));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void toggleLeaderboardOptIn_success_updatesAndReturnsOk() throws Exception {
        final User user = User.builder().id(1L).email("u@test.com").role(Role.PATIENT).password("p").status("ACTIVE").build();
        when(userRepo.findById(1L)).thenReturn(Optional.of(user));
        when(userRepo.save(user)).thenReturn(user);

        final ResponseEntity<?> response = controller.toggleLeaderboardOptIn(1L, Map.of("optIn", true));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(user.getLeaderboardOptIn()).isTrue();
    }

    // ─── getLeaderboard ───────────────────────────────────────────────────────

    @Test
    void getLeaderboard_returnsOkWithEntries() throws Exception {
        final List<LeaderboardEntry> entries = List.of(new LeaderboardEntry(1L, "Smith", "John", 100, 2, null));
        when(userRepo.findLeaderboard()).thenReturn(entries);

        final ResponseEntity<List<LeaderboardEntry>> response = controller.getLeaderboard();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(entries);
    }

    // ─── checkEmailExists ─────────────────────────────────────────────────────

    @Test
    void checkEmailExists_userFound_returnsExistsTrue() throws Exception {
        final User user = User.builder().id(5L).email("found@test.com").role(Role.PATIENT).password("p").status("ACTIVE").build();
        when(userRepo.findByEmail("found@test.com")).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.checkEmailExists("found@test.com");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("exists", true);
        assertThat(body).containsKey("role");
        assertThat(body).containsKey("userId");
    }

    @Test
    void checkEmailExists_userNotFound_returnsExistsFalse() throws Exception {
        when(userRepo.findByEmail("missing@test.com")).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.checkEmailExists("missing@test.com");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("exists", false);
    }
}
