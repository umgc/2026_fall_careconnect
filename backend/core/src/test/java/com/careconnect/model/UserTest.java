package com.careconnect.model;

import com.careconnect.security.Role;
import org.junit.jupiter.api.Test;

import java.sql.Timestamp;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class UserTest {

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final User user = new User();

        assertThat(user).isNotNull();
        assertThat(user.getId()).isNull();
        assertThat(user.getName()).isNull();
        assertThat(user.getEmail()).isNull();
        assertThat(user.getRole()).isNull();
        assertThat(user.getLoginStreak()).isEqualTo(0);       // @Builder.Default initialises in no-arg ctor
        assertThat(user.getLeaderboardOptIn()).isTrue();      // @Builder.Default initialises in no-arg ctor
        assertThat(user.getIsVerified()).isFalse();           // @Builder.Default initialises in no-arg ctor
        assertThat(user.getStatus()).isEqualTo("ACTIVE");     // @Builder.Default initialises in no-arg ctor
    }

    // ─── Builder defaults ─────────────────────────────────────────────────────

    @Test
    void builder_defaults() throws Exception {
        final User user = User.builder()
                .email("test@example.com")
                .password("pass")
                .role(Role.PATIENT)
                .build();

        assertThat(user.getLoginStreak()).isEqualTo(0);
        assertThat(user.getLeaderboardOptIn()).isTrue();
        assertThat(user.getIsVerified()).isFalse();
        assertThat(user.getStatus()).isEqualTo("ACTIVE");
    }

    // ─── Builder all fields ───────────────────────────────────────────────────

    @Test
    void builder_allFields() throws Exception {
        final Timestamp now = new Timestamp(System.currentTimeMillis());
        final LocalDate today = LocalDate.now();

        final User user = User.builder()
                .id(1L)
                .name("John Doe")
                .email("john@example.com")
                .password("secret")
                .passwordHash("hashed")
                .lastLoginDate(today)
                .loginStreak(5)
                .leaderboardOptIn(false)
                .role(Role.CAREGIVER)
                .isVerified(true)
                .verificationToken("tok123")
                .paymentCustomerId("cus_abc")
                .createdAt(now)
                .lastLogin(now)
                .profileImageUrl("http://example.com/img.png")
                .status("ACTIVE")
                .build();

        assertThat(user.getId()).isEqualTo(1L);
        assertThat(user.getName()).isEqualTo("John Doe");
        assertThat(user.getEmail()).isEqualTo("john@example.com");
        assertThat(user.getPassword()).isEqualTo("secret");
        assertThat(user.getPasswordHash()).isEqualTo("hashed");
        assertThat(user.getLastLoginDate()).isEqualTo(today);
        assertThat(user.getLoginStreak()).isEqualTo(5);
        assertThat(user.getLeaderboardOptIn()).isFalse();
        assertThat(user.getRole()).isEqualTo(Role.CAREGIVER);
        assertThat(user.getIsVerified()).isTrue();
        assertThat(user.getVerificationToken()).isEqualTo("tok123");
        assertThat(user.getPaymentCustomerId()).isEqualTo("cus_abc");
        assertThat(user.getStatus()).isEqualTo("ACTIVE");
    }

    // ─── isActive() ───────────────────────────────────────────────────────────

    @Test
    void isActive_activeStatus_returnsTrue() throws Exception {
        final User user = new User();
        user.setStatus("ACTIVE");

        assertThat(user.isActive()).isTrue();
    }

    @Test
    void isActive_inactiveStatus_returnsFalse() throws Exception {
        final User user = new User();
        user.setStatus("INACTIVE");

        assertThat(user.isActive()).isFalse();
    }

    @Test
    void isActive_caseInsensitive_returnsTrue() throws Exception {
        final User user = new User();
        user.setStatus("active");

        assertThat(user.isActive()).isTrue();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final User user = new User();

        user.setId(2L);
        user.setName("Jane");
        user.setEmail("jane@example.com");
        user.setRole(Role.PATIENT);
        user.setIsVerified(true);
        user.setVerificationToken("tok456");
        user.setStatus("ACTIVE");
        user.setProfileImageUrl("http://img.com/photo.jpg");
        user.setPaymentCustomerId("cus_xyz");
        user.setLastLoginDate(LocalDate.now());
        user.setLoginStreak(3);
        user.setLeaderboardOptIn(true);

        assertThat(user.getId()).isEqualTo(2L);
        assertThat(user.getName()).isEqualTo("Jane");
        assertThat(user.getEmail()).isEqualTo("jane@example.com");
        assertThat(user.getRole()).isEqualTo(Role.PATIENT);
        assertThat(user.getIsVerified()).isTrue();
        assertThat(user.getVerificationToken()).isEqualTo("tok456");
        assertThat(user.getStatus()).isEqualTo("ACTIVE");
        assertThat(user.getProfileImageUrl()).isEqualTo("http://img.com/photo.jpg");
        assertThat(user.getPaymentCustomerId()).isEqualTo("cus_xyz");
        assertThat(user.getLoginStreak()).isEqualTo(3);
        assertThat(user.getLeaderboardOptIn()).isTrue();
    }

    @Test
    void credentialsAreNeverSerialized() throws Exception {
        // Arrange
        final User user = User.builder()
                .id(9L).email("patient@example.com").role(Role.PATIENT)
                .password("$2a$10$hash").passwordHash("$2a$10$hash").verificationToken("token-123")
                .build();

        // Act
        final String json = new com.fasterxml.jackson.databind.ObjectMapper()
                .findAndRegisterModules().writeValueAsString(user);

        // Assert
        assertThat(json).contains("patient@example.com")
                .doesNotContain("password").doesNotContain("$2a$10$hash")
                .doesNotContain("verificationToken").doesNotContain("token-123");
    }

    @Test
    void credentialsCannotBeSetFromJson() throws Exception {
        final User user = new com.fasterxml.jackson.databind.ObjectMapper().readValue(
                "{\"id\":9,\"password\":\"x\",\"passwordHash\":\"y\",\"verificationToken\":\"z\"}",
                User.class);

        assertThat(user.getPassword()).isNull();
        assertThat(user.getPasswordHash()).isNull();
        assertThat(user.getVerificationToken()).isNull();
    }
}
