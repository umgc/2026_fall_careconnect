package com.careconnect.controller;

import com.careconnect.dto.ai.hitl.HitlDetailResponse;
import com.careconnect.dto.ai.hitl.HitlQueueItem;
import com.careconnect.dto.ai.hitl.HitlRejectRequest;
import com.careconnect.dto.ai.hitl.HitlReleaseRequest;
import com.careconnect.dto.ai.hitl.HitlStatusResponse;
import com.careconnect.model.User;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.Role;
import com.careconnect.service.ai.hitl.HitlConflictException;
import com.careconnect.service.ai.hitl.HitlNotFoundException;
import com.careconnect.service.ai.hitl.HitlService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class HitlControllerTest {

    @Mock
    private HitlService hitlService;
    @Mock
    private SecurityUtil securityUtil;

    private MockMvc mockMvc;
    private User caller;

    private static HitlDetailResponse detail(
            final UUID heldItemId,
            final String status,
            final String deliveryStatus) {
        return new HitlDetailResponse(
                heldItemId,
                42L,
                7L,
                status,
                deliveryStatus,
                List.of("MEDICATION_CHANGE"),
                "Should I stop taking metformin?",
                "draft",
                "DELIVERED".equals(deliveryStatus) ? "draft" : null,
                "[]",
                "[]",
                Instant.now(),
                Instant.now().plusSeconds(3600),
                Instant.now(),
                99L,
                "notes");
    }

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(
                        new HitlController(hitlService, securityUtil))
                .build();
        caller = new User();
        caller.setId(7L);
        caller.setRole(Role.CAREGIVER);
        lenient().when(securityUtil.resolveCurrentUser()).thenReturn(caller);
    }

    @Test
    @DisplayName("status poll returns held redacted contract")
    void status_returnsHeldContract() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        final Instant expiresAt = Instant.parse("2026-07-24T12:00:00Z");
        when(hitlService.getStatus(eq(heldItemId), any())).thenReturn(new HitlStatusResponse(
                heldItemId,
                "PENDING_REVIEW",
                "HELD",
                HitlService.REVIEWING_MESSAGE,
                null,
                List.of(),
                expiresAt,
                null,
                null));

        mockMvc.perform(get("/api/ai/hitl/{id}/status", heldItemId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.heldItemId").value(heldItemId.toString()))
                .andExpect(jsonPath("$.status").value("PENDING_REVIEW"))
                .andExpect(jsonPath("$.deliveryStatus").value("HELD"))
                .andExpect(jsonPath("$.answer").doesNotExist())
                .andExpect(jsonPath("$.message").value(HitlService.REVIEWING_MESSAGE));
    }

    @Test
    @DisplayName("versioned status URL is wired")
    void status_versionedUrl() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        when(hitlService.getStatus(eq(heldItemId), any())).thenReturn(new HitlStatusResponse(
                heldItemId,
                "PENDING_REVIEW",
                "HELD",
                HitlService.REVIEWING_MESSAGE,
                null,
                List.of(),
                Instant.now(),
                null,
                null));

        mockMvc.perform(get("/v1/api/ai/hitl/{id}/status", heldItemId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.deliveryStatus").value("HELD"));
    }

    @Test
    void queue_returnsItems() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        when(hitlService.listQueue(any())).thenReturn(List.of(new HitlQueueItem(
                heldItemId,
                42L,
                List.of("MEDICATION_CHANGE"),
                "Should I stop taking metformin?",
                "ASK_AI",
                Instant.now(),
                Instant.now().plusSeconds(3600))));

        mockMvc.perform(get("/api/ai/hitl/queue"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].heldItemId").value(heldItemId.toString()))
                .andExpect(jsonPath("$[0].triggerCodes[0]").value("MEDICATION_CHANGE"))
                .andExpect(jsonPath("$[0].queryPreview").value("Should I stop taking metformin?"));
    }

    @Test
    void release_delegatesToService() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        when(hitlService.release(eq(heldItemId), any(), eq("edited"), eq("ok")))
                .thenReturn(detail(heldItemId, "DELIVERED", "DELIVERED"));

        mockMvc.perform(post("/api/ai/hitl/{id}/release", heldItemId)
                        .contentType("application/json")
                        .content("{\"editedAnswer\":\"edited\",\"notes\":\"ok\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DELIVERED"))
                .andExpect(jsonPath("$.deliveryStatus").value("DELIVERED"));

        verify(hitlService).release(eq(heldItemId), any(), eq("edited"), eq("ok"));
    }

    @Test
    void reject_delegatesToService() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        when(hitlService.reject(eq(heldItemId), any(), eq("unsafe")))
                .thenReturn(detail(heldItemId, "REJECTED", "WITHHELD_PERMANENTLY"));

        mockMvc.perform(post("/api/ai/hitl/{id}/reject", heldItemId)
                        .contentType("application/json")
                        .content("{\"reason\":\"unsafe\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("REJECTED"));

        verify(hitlService).reject(eq(heldItemId), any(), eq("unsafe"));
    }

    @Test
    void release_emptyBodyUsesNullFields() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        when(hitlService.release(eq(heldItemId), any(), isNull(), isNull()))
                .thenReturn(detail(heldItemId, "DELIVERED", "DELIVERED"));

        mockMvc.perform(post("/api/ai/hitl/{id}/release", heldItemId)
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isOk());

        verify(hitlService).release(eq(heldItemId), any(), isNull(), isNull());
    }

    @Test
    @DisplayName("missing held item returns 404")
    void notFound_mapsTo404() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        when(hitlService.getStatus(eq(heldItemId), any()))
                .thenThrow(new HitlNotFoundException("Held item not found"));

        mockMvc.perform(get("/api/ai/hitl/{id}/status", heldItemId))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("NOT_FOUND"));
    }

    @Test
    @DisplayName("release conflict returns 409")
    void conflict_mapsTo409() throws Exception {
        final UUID heldItemId = UUID.randomUUID();
        when(hitlService.release(eq(heldItemId), any(), any(), any()))
                .thenThrow(new HitlConflictException("Held item is not pending review"));

        mockMvc.perform(post("/api/ai/hitl/{id}/release", heldItemId)
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("CONFLICT"));
    }

    @Test
    void statusEndpointRequiresAiFeaturePermission() throws Exception {
        final RequirePermission requirement = HitlController.class
                .getMethod("status", UUID.class)
                .getAnnotation(RequirePermission.class);

        assertThat(requirement).isNotNull();
        assertThat(requirement.value()).isEqualTo(Permission.USE_AI_FEATURES);
    }

    @Test
    void reviewerEndpointsRequireReviewAiHoldsPermission() throws Exception {
        assertThat(HitlController.class.getMethod("queue")
                .getAnnotation(RequirePermission.class).value())
                .isEqualTo(Permission.REVIEW_AI_HOLDS);
        assertThat(HitlController.class.getMethod("detail", UUID.class)
                .getAnnotation(RequirePermission.class).value())
                .isEqualTo(Permission.REVIEW_AI_HOLDS);
        assertThat(HitlController.class.getMethod("release", UUID.class, HitlReleaseRequest.class)
                .getAnnotation(RequirePermission.class).value())
                .isEqualTo(Permission.REVIEW_AI_HOLDS);
        assertThat(HitlController.class.getMethod("reject", UUID.class, HitlRejectRequest.class)
                .getAnnotation(RequirePermission.class).value())
                .isEqualTo(Permission.REVIEW_AI_HOLDS);
    }
}
