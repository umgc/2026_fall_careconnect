package com.careconnect.repository;

import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.dto.LeaderboardEntry;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.careconnect.dto.LeaderboardEntry;
import com.careconnect.model.User;
import com.careconnect.security.Role;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    // Spring Data JPA query methods for the 'roles' collection
    Optional<User> findByEmailAndRolesContaining(String email, Role role);

    List<User> findByRolesContaining(Role role);

    boolean existsByEmailAndRolesContaining(String email, Role role);

    // Backward-compatibility delegate methods for existing callers
    default Optional<User> findByEmailAndRole(String email, Role role) {
        return findByEmailAndRolesContaining(email, role);
    }

    default List<User> findByRole(Role role) {
        return findByRolesContaining(role);
    }

    Optional<User> findByVerificationToken(String token);

    List<User> findByNameContainingIgnoreCaseOrEmailContainingIgnoreCase(String name, String email);

    Optional<User> findByPaymentCustomerId(String paymentCustomerId);

    @Query("SELECT u.id FROM User u " +
           "JOIN Friendship f ON " +
           "(f.user1.id = :userId AND f.user2.id = u.id OR " +
           "f.user2.id = :userId AND f.user1.id = u.id) " +
           "WHERE f.status = 'CONFIRMED'")
    List<Long> findConfirmedFriendIds(@Param("userId") Long userId);

    @Query("SELECT new com.careconnect.dto.LeaderboardEntry(" +
           "u.id, p.lastName, p.firstName, xp.xp, xp.level, u.profileImageUrl) " +
           "FROM User u " +
           "JOIN XPProgress xp ON xp.userId = u.id " +
           "JOIN Patient p ON p.user.id = u.id " +
           "WHERE u.leaderboardOptIn = true " +
           "ORDER BY xp.xp DESC")
    List<LeaderboardEntry> findLeaderboard();
}