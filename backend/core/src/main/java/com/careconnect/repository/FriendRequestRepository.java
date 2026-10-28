package com.careconnect.repository;

import com.careconnect.model.FriendRequest;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface FriendRequestRepository extends JpaRepository<FriendRequest, Long> {
    boolean existsByFromUserIdAndToUserId(Long fromUserId, Long toUserId);

    List<FriendRequest> findByToUserIdAndStatus(Long toUserId, String status);

    List<FriendRequest> findByStatus(String status);

    // Two users are friends once a request between them, sent either way, was accepted
    @Query("SELECT CASE WHEN COUNT(r) > 0 THEN true ELSE false END FROM FriendRequest r " +
            "WHERE r.status = 'accepted' " +
            "AND ((r.fromUserId = :userA AND r.toUserId = :userB) " +
            "OR (r.fromUserId = :userB AND r.toUserId = :userA))")
    boolean existsAcceptedBetween(@Param("userA") Long userA, @Param("userB") Long userB);

}
