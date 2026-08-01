package com.careconnect.service.ai.hitl;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.model.ai.hitl.AiHeldItemStatus;
import com.careconnect.repository.ai.hitl.AiHeldItemRepository;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class HitlOpenHoldWriterTest {

    @Mock
    private AiHeldItemRepository heldItemRepository;

    @InjectMocks
    private HitlOpenHoldWriter writer;

    @Test
    @DisplayName("insertOpenHold persists via saveAndFlush")
    void insertOpenHold_savesAndFlushes() {
        final AiHeldItem item = AiHeldItem.builder()
                .id(UUID.randomUUID())
                .patientId(42L)
                .status(AiHeldItemStatus.PENDING_REVIEW)
                .createdAt(Instant.now())
                .build();
        when(heldItemRepository.saveAndFlush(item)).thenReturn(item);

        final AiHeldItem saved = writer.insertOpenHold(item);

        assertThat(saved).isSameAs(item);
        verify(heldItemRepository).saveAndFlush(item);
    }
}
