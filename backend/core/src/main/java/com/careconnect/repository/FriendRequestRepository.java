package com.careconnect.repository;

import com.careconnect.model.FriendRequest;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FriendRequestRepository extends JpaRepository<FriendRequest, Long> {
    boolean existsByFromUserIdAndToUserId(Long fromUserId, Long toUserId);

    List<FriendRequest> findByToUserIdAndStatus(Long toUserId, String status);

    List<FriendRequest> findByStatus(String status);

}
