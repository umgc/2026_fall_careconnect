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

@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    Optional<User> findByVerificationToken(String token);

    Optional<User> findByPaymentCustomerId(String paymentCustomerId);

    List<User> findByNameContainingIgnoreCaseOrEmailContainingIgnoreCase(String name, String email);

    Optional<User> findByEmailAndRolesContaining(String email, Role role);

    @Query("SELECT u FROM User u JOIN u.roles r WHERE u.email = :email AND r = :role")
    Optional<User> findByEmailAndRole(@Param("email") String email, @Param("role") Role role);

    @Query("SELECT u FROM User u ORDER BY u.id ASC")
    List<LeaderboardEntry> findLeaderboard();

    @Query("SELECT u.id FROM User u " +
           "JOIN Friendship f ON " +
           "(f.user1.id = :userId AND f.user2.id = u.id OR " +
           "f.user2.id = :userId AND f.user1.id = u.id) " +
           "WHERE f.status = 'CONFIRMED'")
    List<Long> findConfirmedFriendIds(@Param("userId") Long userId);
}