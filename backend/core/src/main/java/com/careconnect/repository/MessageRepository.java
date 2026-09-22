package com.careconnect.repository;

import com.careconnect.model.Message;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface MessageRepository extends JpaRepository<Message, Long> {

    // Get messages between two users, ordered by timestamp
    @Query("SELECT m FROM Message m " +
            "WHERE (m.senderId = :user1 AND m.receiverId = :user2) " +
            "OR (m.senderId = :user2 AND m.receiverId = :user1) " +
            "ORDER BY m.timestamp ASC")
    List<Message> findConversation(@Param("user1") Long user1, @Param("user2") Long user2);

    // Optionally for inbox preview: last message per user
    @Query("SELECT m FROM Message m WHERE m.senderId = :userId OR m.receiverId = :userId ORDER BY m.timestamp DESC")
    List<Message> findAllUserMessages(@Param("userId") Long userId);

    @Query("SELECT CASE WHEN COUNT(m) > 0 THEN true ELSE false END FROM Message m " +
            "WHERE m.attachmentId = :attachmentId " +
            "AND (m.senderId = :userId OR m.receiverId = :userId)")
    boolean existsAttachmentInUserConversation(
            @Param("attachmentId") Long attachmentId,
            @Param("userId") Long userId
    );
}