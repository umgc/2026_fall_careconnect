package com.careconnect.repository;

import com.careconnect.model.ChatMessage;
import com.careconnect.model.ChatConversation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {

    List<ChatMessage> findByConversationOrderByCreatedAtAsc(ChatConversation conversation);

    List<ChatMessage> findByConversationOrderByCreatedAtDesc(ChatConversation conversation);

    @Query(value = "SELECT * FROM chat_messages WHERE conversation_id = :#{#conversation.id} ORDER BY created_at ASC LIMIT :limit", nativeQuery = true)
    List<ChatMessage> findTopNByConversationOrderByCreatedAtAsc(
            @Param("conversation") ChatConversation conversation,
            @Param("limit") Integer limit
    );

    @Query("SELECT COUNT(m) FROM ChatMessage m WHERE m.conversation = :conversation")
    int countByConversation(@Param("conversation") ChatConversation conversation);

    @Query("SELECT SUM(m.tokensUsed) FROM ChatMessage m WHERE m.conversation = :conversation")
    Integer sumTokensUsedByConversation(@Param("conversation") ChatConversation conversation);
}
