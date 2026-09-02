package com.careconnect.repository;

import com.careconnect.model.Post;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PostRepository extends JpaRepository<Post, Long> {
    List<Post> findAllByUserIdOrderByCreatedAtDesc(Long userId);

    List<Post> findAllByOrderByCreatedAtDesc(); // For global feed

    List<Post> findAllByUserIdInOrderByCreatedAtDesc(List<Long> userIds);

    long countByUserId(Long userId);
}
