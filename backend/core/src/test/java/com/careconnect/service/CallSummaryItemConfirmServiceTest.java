package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.SummaryItemConfirmRequest;
import com.careconnect.dto.SummaryItemConfirmResponse;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallSummaryItemDecision;
import com.careconnect.model.User;
import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.repository.CallSummaryItemDecisionRepository;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.security.Role;
import com.careconnect.service.ai.hitl.HitlService;
import com.careconnect.service.ai.safety.SafetyOutcome;
import com.careconnect.service.ai.safety.SafetyPipeline;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
@DisplayName("CallSummaryItemConfirmService Tests")
class CallSummaryItemConfirmServiceTest {

    private static final String CALL_ID = "call-42";
    private static final Long PATIENT_ID = 7L;

    @Mock
    private CallSummaryRepository callSummaryRepository;

    @Mock
    private CallSummaryItemDecisionRepository decisionRepository;

    @Mock
    private SafetyPipeline safetyPipeline;

    @Mock
    private HitlService hitlService;

    private CallSummaryItemConfirmService service;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        service = new CallSummaryItemConfirmService(
                callSummaryRepository, decisionRepository, objectMapper, safetyPipeline, hitlService);
    }

    private User actor() {
        return User.builder().id(5L).role(Role.CAREGIVER).build();
    }

    private CallSummary summaryWithItems(final String summaryJson) {
        final CallSummary summary = new CallSummary();
        summary.setId(1L);
        summary.setCallId(CALL_ID);
        summary.setPatientId(PATIENT_ID);
        summary.setSummaryJson(summaryJson);
        return summary;
    }

    private static String actionItemPayload(final String itemId) {
        return "{\"actionItems\":[{\"itemId\":\"" + itemId + "\",\"text\":\"Schedule follow-up\","
                + "\"needsConfirmation\":true}],\"appointments\":[],\"careInstructions\":[]}";
    }

    private static String medicationInstructionPayload(final String itemId, final String text) {
        return "{\"actionItems\":[],\"appointments\":[],\"careInstructions\":["
                + "{\"itemId\":\"" + itemId + "\",\"type\":\"medication\",\"text\":\""
                + text + "\",\"needsConfirmation\":true}]}";
    }

    @Test
    @DisplayName("confirm throws when callId is blank")
    void confirm_throwsWhenCallIdBlank() {
        assertThatThrownBy(() -> service.confirm(
                "", "item-1", actor(), new SummaryItemConfirmRequest("approve", null, null)))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("confirm throws when decision is invalid")
    void confirm_throwsWhenDecisionInvalid() {
        assertThatThrownBy(() -> service.confirm(
                CALL_ID, "item-1", actor(), new SummaryItemConfirmRequest("maybe", null, null)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("decision");
    }

    @Test
    @DisplayName("confirm throws when no summary exists for the call")
    void confirm_throwsWhenSummaryMissing() {
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.confirm(
                CALL_ID, "item-1", actor(), new SummaryItemConfirmRequest("approve", null, null)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No summary found");
    }

    @Test
    @DisplayName("confirm throws when item is not found in the summary payload")
    void confirm_throwsWhenItemNotFound() {
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summaryWithItems(actionItemPayload("item-1"))));

        assertThatThrownBy(() -> service.confirm(
                CALL_ID, "missing-item", actor(),
                new SummaryItemConfirmRequest("approve", null, null)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Item not found");
    }

    @Test
    @DisplayName("approving a non-medication action item records a decision and clears the gate")
    void confirm_approveActionItem_recordsDecision() {
        final CallSummary summary = summaryWithItems(actionItemPayload("item-1"));
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summary));
        when(decisionRepository.save(any(CallSummaryItemDecision.class)))
                .thenAnswer(invocation -> {
                    final CallSummaryItemDecision decision = invocation.getArgument(0);
                    decision.setId(99L);
                    return decision;
                });

        final SummaryItemConfirmResponse response = service.confirm(
                CALL_ID, "item-1", actor(),
                new SummaryItemConfirmRequest("approve", "calendar", "looks good"));

        assertThat(response.held()).isFalse();
        assertThat(response.decision()).isEqualTo("approve");
        assertThat(response.decisionId()).isEqualTo(99L);

        final ArgumentCaptor<CallSummaryItemDecision> decisionCaptor =
                ArgumentCaptor.forClass(CallSummaryItemDecision.class);
        verify(decisionRepository).save(decisionCaptor.capture());
        assertThat(decisionCaptor.getValue().getItemType()).isEqualTo("action_item");
        assertThat(decisionCaptor.getValue().getDestination()).isEqualTo("calendar");
        assertThat(decisionCaptor.getValue().getDecidedByUserId()).isEqualTo(5L);

        final ArgumentCaptor<CallSummary> summaryCaptor = ArgumentCaptor.forClass(CallSummary.class);
        verify(callSummaryRepository).save(summaryCaptor.capture());
        assertThat(summaryCaptor.getValue().getSummaryJson()).contains("\"needsConfirmation\":false");
        verifyNoHitlInteraction();
    }

    @Test
    @DisplayName("approving a medication instruction that trips safety review creates a HITL hold")
    void confirm_medicationInstructionHeldByTierClassifier() {
        final CallSummary summary = summaryWithItems(
                medicationInstructionPayload("item-2", "Stop taking metformin"));
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summary));
        when(hitlService.findOpenHold(any(), any())).thenReturn(Optional.empty());
        when(safetyPipeline.process(any())).thenReturn(
                SafetyOutcome.holdTier2(List.of("MEDICATION_CHANGE"), List.of()));
        final AiHeldItem held = AiHeldItem.builder().id(UUID.randomUUID()).build();
        when(hitlService.createHold(any(), any(), any())).thenReturn(held);

        final SummaryItemConfirmResponse response = service.confirm(
                CALL_ID, "item-2", actor(),
                new SummaryItemConfirmRequest("approve", null, null));

        assertThat(response.held()).isTrue();
        assertThat(response.heldItemId()).isEqualTo(held.getId());
        assertThat(response.decision()).isNull();
        verify(hitlService).createHold(any(), any(), any());
        verify(decisionRepository, never()).save(any());
        verify(callSummaryRepository, never()).save(any());
    }

    @Test
    @DisplayName("reuses an open HITL hold instead of creating a duplicate on retry")
    void confirm_medicationInstructionReusesOpenHold() {
        final CallSummary summary = summaryWithItems(
                medicationInstructionPayload("item-2", "Stop taking metformin"));
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summary));
        final AiHeldItem open = AiHeldItem.builder().id(UUID.randomUUID()).build();
        when(hitlService.findOpenHold(
                eq("CALL_SUMMARY"),
                eq(CallSummaryItemConfirmService.summaryItemCorrelationKey(CALL_ID, "item-2"))))
                .thenReturn(Optional.of(open));

        final SummaryItemConfirmResponse response = service.confirm(
                CALL_ID, "item-2", actor(),
                new SummaryItemConfirmRequest("approve", null, null));

        assertThat(response.held()).isTrue();
        assertThat(response.heldItemId()).isEqualTo(open.getId());
        verify(hitlService, never()).createHold(any(), any(), any());
        verify(safetyPipeline, never()).process(any());
    }

    @Test
    @DisplayName("fails closed when medication instruction summary has no patientId")
    void confirm_medicationInstructionFailsClosedWithoutPatientId() {
        final CallSummary summary = summaryWithItems(
                medicationInstructionPayload("item-2", "Stop taking metformin"));
        summary.setPatientId(null);
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summary));

        assertThatThrownBy(() -> service.confirm(
                CALL_ID, "item-2", actor(),
                new SummaryItemConfirmRequest("approve", null, null)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("patientId");
        verify(hitlService, never()).createHold(any(), any(), any());
        verify(decisionRepository, never()).save(any());
    }

    @Test
    @DisplayName("approving a medication instruction that passes safety review records normally")
    void confirm_medicationInstructionDeliveredNormally() {
        final CallSummary summary = summaryWithItems(
                medicationInstructionPayload("item-3", "Continue current medication as prescribed"));
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summary));
        when(hitlService.findOpenHold(any(), any())).thenReturn(Optional.empty());
        when(safetyPipeline.process(any())).thenReturn(
                SafetyOutcome.deliverTier1(List.of(), List.of(), "none"));
        when(decisionRepository.save(any(CallSummaryItemDecision.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final SummaryItemConfirmResponse response = service.confirm(
                CALL_ID, "item-3", actor(),
                new SummaryItemConfirmRequest("approve", null, null));

        assertThat(response.held()).isFalse();
        assertThat(response.decision()).isEqualTo("approve");
        verify(hitlService, never()).createHold(any(), any(), any());
        verify(decisionRepository).save(any(CallSummaryItemDecision.class));
    }

  @Test
    @DisplayName("returns existing decision when item already confirmed")
    void confirm_alreadyConfirmed_returnsPriorDecisionWithoutInsert() {
        final CallSummary summary = summaryWithItems(
                "{\"actionItems\":[{\"itemId\":\"item-1\",\"text\":\"Schedule follow-up\","
                        + "\"needsConfirmation\":false}],\"appointments\":[],\"careInstructions\":[]}");
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summary));
        final CallSummaryItemDecision prior = CallSummaryItemDecision.builder()
                .id(77L)
                .summaryId(1L)
                .itemId("item-1")
                .decision("approve")
                .build();
        when(decisionRepository.findTopBySummaryIdAndItemIdOrderByDecidedAtDesc(1L, "item-1"))
                .thenReturn(Optional.of(prior));

        final SummaryItemConfirmResponse response = service.confirm(
                CALL_ID, "item-1", actor(),
                new SummaryItemConfirmRequest("approve", null, null));

        assertThat(response.decision()).isEqualTo("approve");
        assertThat(response.decisionId()).isEqualTo(77L);
        assertThat(response.held()).isFalse();
        verify(decisionRepository, never()).save(any());
        verify(callSummaryRepository, never()).save(any());
    }

    @Test
    @DisplayName("declining a medication instruction skips the safety pipeline")
    void confirm_declineMedicationInstruction_skipsSafetyPipeline() {
        final CallSummary summary = summaryWithItems(
                medicationInstructionPayload("item-4", "Stop taking metformin"));
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(CALL_ID))
                .thenReturn(Optional.of(summary));
        when(decisionRepository.save(any(CallSummaryItemDecision.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final SummaryItemConfirmResponse response = service.confirm(
                CALL_ID, "item-4", actor(),
                new SummaryItemConfirmRequest("decline", null, "not applicable"));

        assertThat(response.held()).isFalse();
        assertThat(response.decision()).isEqualTo("decline");
        verifyNoHitlInteraction();
        verify(decisionRepository).save(any(CallSummaryItemDecision.class));
    }

    private void verifyNoHitlInteraction() {
        verify(safetyPipeline, never()).process(any());
        verify(hitlService, never()).createHold(any(), any(), any());
    }
}
