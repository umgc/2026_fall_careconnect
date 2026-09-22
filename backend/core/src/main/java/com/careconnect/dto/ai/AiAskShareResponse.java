package com.careconnect.dto.ai;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record AiAskShareResponse(
        UUID shareId,
        Long patientId,
        UUID sessionId,
        List<Long> recipientUserIds,
        int messageCount,
        Instant createdAt,
        String transcriptJson) {
}
