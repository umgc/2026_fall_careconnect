package com.careconnect.service.ai.hitl;

import com.careconnect.dto.ai.hitl.HitlDetailResponse;
import com.careconnect.dto.ai.hitl.HitlQueueItem;
import com.careconnect.dto.ai.hitl.HitlStatusResponse;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.model.ai.hitl.AiHeldItemStatus;
import com.careconnect.model.ai.hitl.AiSafetyAuditEvent;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ai.hitl.AiHeldItemRepository;
import com.careconnect.repository.ai.hitl.AiSafetyAuditEventRepository;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.ai.audit.AiAskAuditService;
import com.careconnect.service.ai.safety.SafetyInput;
import com.careconnect.service.ai.safety.SafetyOutcome;
import com.careconnect.service.ai.safety.SafetyPipeline;
import com.careconnect.service.ai.safety.ValidationFinding;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class HitlServiceTest {

    @Mock
    private AiHeldItemRepository heldItemRepository;
    @Mock
    private AiSafetyAuditEventRepository auditEventRepository;
    @Mock
    private AiAskAuditService askAuditService;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock
    private FamilyMemberService familyMemberService;
    @Mock
    private SafetyPipeline safetyPipeline;

    @Mock
    private HitlOpenHoldWriter openHoldWriter;

    private HitlService service;

    @BeforeEach
    void setUp() {
        service = new HitlService(
                heldItemRepository,
                auditEventRepository,
                askAuditService,
                patientRepository,
                caregiverPatientLinkService,
                familyMemberService,
                safetyPipeline,
                openHoldWriter,
                new ObjectMapper(),
                72L);
        org.mockito.Mockito.lenient().when(openHoldWriter.insertOpenHold(any(AiHeldItem.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        org.mockito.Mockito.lenient().when(heldItemRepository.save(any(AiHeldItem.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        org.mockito.Mockito.lenient()
                .when(heldItemRepository
                        .findFirstByPatientIdAndSourceSurfaceAndQueryTextHashAndStatusOrderByCreatedAtDesc(
                                any(), any(), any(), any()))
                .thenReturn(Optional.empty());
        org.mockito.Mockito.lenient().when(auditEventRepository.save(any(AiSafetyAuditEvent.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        stubLinkedPatient(42L, 7L);
        org.mockito.Mockito.lenient()
                .when(caregiverPatientLinkService.hasAccessToPatient(eq(99L), eq(7L)))
                .thenReturn(true);
        org.mockito.Mockito.lenient()
                .when(heldItemRepository.updateOutcomeIfStatus(
                        any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(1);
        org.mockito.Mockito.lenient()
                .when(heldItemRepository.expireIfPending(any(), any()))
                .thenReturn(1);
        org.mockito.Mockito.lenient()
                .when(safetyPipeline.process(any(SafetyInput.class)))
                .thenReturn(SafetyOutcome.deliverTier1(List.of(), List.of(), "none"));
    }

    @Test
    @DisplayName("createHold persists PENDING_REVIEW item and HITL_HELD audit")
    void createHold_persistsPendingItem() {
        final SafetyInput input = safetyInput("Should I stop taking metformin?", "Draft answer");
        final SafetyOutcome outcome = SafetyOutcome.holdTier2(
                List.of("MEDICATION_CHANGE"),
                List.of(new ValidationFinding(
                        ValidationFinding.Severity.WARN,
                        "MEDICATION_CHANGE",
                        "Medication change detected")));

        final AiHeldItem saved = service.createHold(input, outcome, List.of());

        assertThat(saved.getStatus()).isEqualTo(AiHeldItemStatus.PENDING_REVIEW);
        assertThat(saved.getDeliveryStatus()).isEqualTo("HELD");
        assertThat(saved.getDraftAnswer()).isEqualTo("Draft answer");
        assertThat(saved.getQueryText()).isEqualTo("Should I stop taking metformin?");
        assertThat(saved.getQueryTextHash()).isNotBlank();
        assertThat(saved.getTier()).isEqualTo(2);
        assertThat(saved.getExpiresAt()).isAfter(Instant.now());

        final ArgumentCaptor<AiSafetyAuditEvent> auditCaptor =
                ArgumentCaptor.forClass(AiSafetyAuditEvent.class);
        verify(auditEventRepository).save(auditCaptor.capture());
        assertThat(auditCaptor.getValue().getEventType()).isEqualTo("HITL_HELD");
        verify(openHoldWriter).insertOpenHold(any(AiHeldItem.class));
    }

    @Test
    @DisplayName("createHold reuses winner when unique open-hold insert races")
    void createHold_uniqueRace_reusesWinner() {
        final SafetyInput input = safetyInput("Should I stop taking metformin?", "Draft answer");
        final SafetyOutcome outcome = SafetyOutcome.holdTier2(List.of("MEDICATION_CHANGE"), List.of());
        final AiHeldItem winner = AiHeldItem.builder()
                .id(UUID.randomUUID())
                .status(AiHeldItemStatus.PENDING_REVIEW)
                .build();
        when(openHoldWriter.insertOpenHold(any(AiHeldItem.class)))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException("uq"));
        when(heldItemRepository
                        .findFirstByPatientIdAndSourceSurfaceAndQueryTextHashAndStatusOrderByCreatedAtDesc(
                                any(), any(), any(), eq(AiHeldItemStatus.PENDING_REVIEW)))
                .thenReturn(Optional.empty(), Optional.of(winner));

        final AiHeldItem result = service.createHold(input, outcome, List.of());

        assertThat(result).isSameAs(winner);
        verify(auditEventRepository, never()).save(any());
    }

    @Test
    @DisplayName("getStatus redacts answer while PENDING_REVIEW")
    void getStatus_pendingRedactsAnswer() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setDraftAnswer("Secret draft that must not leak");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.status()).isEqualTo(AiHeldItemStatus.PENDING_REVIEW.name());
        assertThat(status.deliveryStatus()).isEqualTo("HELD");
        assertThat(status.answer()).isNull();
        assertThat(status.citations()).isEmpty();
        assertThat(status.disclaimer()).isNull();
        assertThat(status.confirmation()).isNull();
        assertThat(status.message()).isEqualTo(HitlService.REVIEWING_MESSAGE);
    }

    @Test
    @DisplayName("getStatus allows patient of record who was not the requester")
    void getStatus_patientOfRecord_allowed() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setRequesterUserId(99L); // caregiver asked
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.deliveryStatus()).isEqualTo("HELD");
        assertThat(status.answer()).isNull();
    }

    @Test
    @DisplayName("getStatus allows linked caregiver who was not the requester")
    void getStatus_linkedCaregiver_allowedWhileRedacted() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setRequesterUserId(7L); // patient asked
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), reviewer());

        assertThat(status.deliveryStatus()).isEqualTo("HELD");
        assertThat(status.answer()).isNull();
    }

    @Test
    @DisplayName("getStatus denies former requester caregiver after patient link is revoked")
    void getStatus_revokedRequesterCaregiver_forbidden() {
        final AiHeldItem item = pendingItem();
        item.setRequesterUserId(99L);
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(caregiverPatientLinkService.hasAccessToPatient(eq(99L), eq(7L))).thenReturn(false);

        assertThatThrownBy(() -> service.getStatus(item.getId(), reviewer()))
                .isInstanceOf(HitlNotFoundException.class)
                .hasMessageContaining("not found");
        verify(heldItemRepository, never()).expireIfPending(any(), any());
    }

    @Test
    @DisplayName("getDetail exposes original query text to linked reviewer")
    void getDetail_includesQueryText() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlDetailResponse detail = service.getDetail(item.getId(), reviewer());

        assertThat(detail.queryText()).isEqualTo("Should I stop taking metformin?");
        assertThat(detail.draftAnswer()).isEqualTo(item.getDraftAnswer());
    }

    @Test
    @DisplayName("listQueue includes query preview for linked patients")
    void listQueue_includesQueryPreview() throws Exception {
        final AiHeldItem linked = pendingItem();
        when(patientRepository.findIdsLinkedToCaregiver(eq(99L), any()))
                .thenReturn(List.of(42L));
        when(heldItemRepository.findByPatientIdInAndStatusOrderByCreatedAtAsc(
                eq(List.of(42L)), eq(AiHeldItemStatus.PENDING_REVIEW)))
                .thenReturn(List.of(linked));

        final List<HitlQueueItem> queue = service.listQueue(reviewer());

        assertThat(queue).hasSize(1);
        assertThat(queue.get(0).queryPreview()).isEqualTo("Should I stop taking metformin?");
    }

    @Test
    @DisplayName("getStatus denies caller outside patient scope with uniform not-found")
    void getStatus_unlinkedCaller_forbidden() {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        final User stranger = new User();
        stranger.setId(55L);
        stranger.setRole(Role.CAREGIVER);
        when(caregiverPatientLinkService.hasAccessToPatient(eq(55L), eq(7L))).thenReturn(false);

        assertThatThrownBy(() -> service.getStatus(item.getId(), stranger))
                .isInstanceOf(HitlNotFoundException.class)
                .hasMessageContaining("not found");
        verify(heldItemRepository, never()).expireIfPending(any(), any());
    }

    @Test
    @DisplayName("getStatus does not expire before access is authorized")
    void getStatus_unlinkedCaller_doesNotExpire() {
        final AiHeldItem item = pendingItem();
        item.setExpiresAt(Instant.now().minus(1, ChronoUnit.HOURS));
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        final User stranger = new User();
        stranger.setId(55L);
        stranger.setRole(Role.CAREGIVER);
        when(caregiverPatientLinkService.hasAccessToPatient(eq(55L), eq(7L))).thenReturn(false);

        assertThatThrownBy(() -> service.getStatus(item.getId(), stranger))
                .isInstanceOf(HitlNotFoundException.class);
        assertThat(item.getStatus()).isEqualTo(AiHeldItemStatus.PENDING_REVIEW);
        verify(heldItemRepository, never()).expireIfPending(any(), any());
        verify(auditEventRepository, never()).save(any());
    }

    @Test
    @DisplayName("getStatus expires past-due PENDING item without auto-approving")
    void getStatus_expiresPastDuePending() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setExpiresAt(Instant.now().minus(1, ChronoUnit.HOURS));
        item.setDraftAnswer("Would have been auto-approved if buggy");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.status()).isEqualTo(AiHeldItemStatus.EXPIRED.name());
        assertThat(status.deliveryStatus()).isEqualTo("WITHHELD_PERMANENTLY");
        assertThat(status.answer()).isNull();
        assertThat(status.message()).isEqualTo(HitlService.EXPIRED_MESSAGE);
        assertThat(item.getStatus()).isEqualTo(AiHeldItemStatus.EXPIRED);
        assertThat(item.getDeliveryStatus()).isNotEqualTo("DELIVERED");

        verify(heldItemRepository).expireIfPending(eq(item.getId()), any());
        final ArgumentCaptor<AiSafetyAuditEvent> auditCaptor =
                ArgumentCaptor.forClass(AiSafetyAuditEvent.class);
        verify(auditEventRepository).save(auditCaptor.capture());
        assertThat(auditCaptor.getValue().getEventType()).isEqualTo("HITL_EXPIRED");
        verify(askAuditService).appendStandaloneEvent(
                eq(item.getAuditId()),
                eq(AiAskAuditService.HITL_EXPIRED),
                isNull(),
                any());
        verify(askAuditService).recordHitlDeliverySupplement(
                eq(item.getAuditId()),
                eq("WITHHELD_PERMANENTLY"),
                isNull(),
                eq(42L),
                any(),
                isNull());
    }

    @Test
    @DisplayName("expire loses race to release without writing HITL_EXPIRED")
    void expireIfNeeded_releaseWinsRace() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setExpiresAt(Instant.now().minus(1, ChronoUnit.HOURS));
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(heldItemRepository.expireIfPending(eq(item.getId()), any())).thenReturn(0);

        final AiHeldItem delivered = pendingItem();
        delivered.setId(item.getId());
        delivered.setStatus(AiHeldItemStatus.DELIVERED);
        delivered.setDeliveryStatus("DELIVERED");
        delivered.setFinalAnswer("Released answer");
        when(heldItemRepository.findById(item.getId()))
                .thenReturn(Optional.of(item))
                .thenReturn(Optional.of(delivered));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.deliveryStatus()).isEqualTo("DELIVERED");
        assertThat(status.answer()).isEqualTo("Released answer");
        assertThat(status.disclaimer()).isNotNull();
        assertThat(status.disclaimer().aiNoticeRequired()).isTrue();
        assertThat(status.confirmation()).isNotNull();
        assertThat(status.confirmation().promptConfirmWithProvider()).isTrue();
        verify(auditEventRepository, never()).save(any());
    }

    @Test
    @DisplayName("release delivers draft and records HITL_RELEASED audit")
    void release_deliversDraft() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlDetailResponse detail = service.release(
                item.getId(), reviewer(), null, "looks good");

        assertThat(detail.status()).isEqualTo(AiHeldItemStatus.DELIVERED.name());
        assertThat(detail.deliveryStatus()).isEqualTo("DELIVERED");
        assertThat(detail.finalAnswer()).isEqualTo(item.getDraftAnswer());
        assertThat(item.getStatus()).isEqualTo(AiHeldItemStatus.DELIVERED);

        final ArgumentCaptor<AiSafetyAuditEvent> auditCaptor =
                ArgumentCaptor.forClass(AiSafetyAuditEvent.class);
        verify(auditEventRepository).save(auditCaptor.capture());
        assertThat(auditCaptor.getValue().getEventType()).isEqualTo("HITL_RELEASED");
        verify(askAuditService).appendStandaloneEvent(
                eq(item.getAuditId()),
                eq(AiAskAuditService.HITL_RELEASED),
                eq(99L),
                any());
        verify(askAuditService).recordHitlDeliverySupplement(
                eq(item.getAuditId()),
                eq("DELIVERED"),
                eq("Draft answer text for review"),
                eq(42L),
                any(),
                eq(99L));
        verify(heldItemRepository).updateOutcomeIfStatus(
                eq(item.getId()),
                eq(AiHeldItemStatus.PENDING_REVIEW),
                eq(AiHeldItemStatus.DELIVERED),
                eq("DELIVERED"),
                eq("Draft answer text for review"),
                eq("[]"),
                eq(99L),
                any(),
                eq("looks good"),
                any());
    }

    @Test
    @DisplayName("release with edited answer clears stored citations")
    void release_editedAnswer_clearsCitations() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setCitationsJson("[{\"citationId\":\"C1\"}]");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlDetailResponse detail = service.release(
                item.getId(), reviewer(), "Clinician rewritten answer", "edited");

        assertThat(detail.finalAnswer()).isEqualTo("Clinician rewritten answer");
        assertThat(detail.citationsJson()).isEqualTo("[]");
        assertThat(item.getCitationsJson()).isEqualTo("[]");
        verify(heldItemRepository).updateOutcomeIfStatus(
                eq(item.getId()),
                eq(AiHeldItemStatus.PENDING_REVIEW),
                eq(AiHeldItemStatus.DELIVERED),
                eq("DELIVERED"),
                eq("Clinician rewritten answer"),
                eq("[]"),
                eq(99L),
                any(),
                eq("edited"),
                any());
        verify(safetyPipeline).process(any(SafetyInput.class));
    }

    @Test
    @DisplayName("release rejects edited answers that still match emergency patterns")
    void release_editedAnswer_emergency_conflicts() {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(safetyPipeline.process(any(SafetyInput.class)))
                .thenReturn(SafetyOutcome.holdTier2(
                        List.of("EMERGENCY_SYMPTOM"),
                        List.of(new ValidationFinding(
                                ValidationFinding.Severity.CRITICAL,
                                "EMERGENCY_SYMPTOM",
                                "Emergency language"))));

        assertThatThrownBy(() -> service.release(
                        item.getId(),
                        reviewer(),
                        "Call 911 for chest pain immediately",
                        "note"))
                .isInstanceOf(HitlConflictException.class)
                .hasMessageContaining("emergency");
        verify(heldItemRepository, never()).updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any());
    }

    @Test
    @DisplayName("UNSUPPORTED_CLAIM holds require a non-blank edited answer before release")
    void release_unsupportedClaim_requiresEditedAnswer() {
        final AiHeldItem item = pendingItem();
        item.setTriggerCodesJson("[\"UNSUPPORTED_CLAIM\"]");
        item.setDraftAnswer("Partial verified draft");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        assertThatThrownBy(() -> service.release(item.getId(), reviewer(), null, null))
                .isInstanceOf(HitlConflictException.class)
                .hasMessageContaining("edited answer");
        assertThatThrownBy(() -> service.release(
                        item.getId(), reviewer(), "Partial verified draft", null))
                .isInstanceOf(HitlConflictException.class)
                .hasMessageContaining("edited answer");
        verify(heldItemRepository, never()).updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any());
    }

    @Test
    @DisplayName("UNSUPPORTED_CLAIM hold releases when reviewer provides an edited answer")
    void release_unsupportedClaim_withEdit_succeeds() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setTriggerCodesJson("[\"UNSUPPORTED_CLAIM\"]");
        item.setDraftAnswer("Partial verified draft");
        item.setCitationsJson("[{\"citationId\":\"C1\"}]");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlDetailResponse detail = service.release(
                item.getId(), reviewer(), "Clinician-approved rewritten answer", "fixed");

        assertThat(detail.deliveryStatus()).isEqualTo("DELIVERED");
        assertThat(detail.finalAnswer()).isEqualTo("Clinician-approved rewritten answer");
        assertThat(detail.citationsJson()).isEqualTo("[]");
    }

    @Test
    @DisplayName("reject withholds permanently and clears final answer")
    void reject_withholdsPermanently() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlDetailResponse detail = service.reject(
                item.getId(), reviewer(), "unsafe claim");

        assertThat(detail.status()).isEqualTo(AiHeldItemStatus.REJECTED.name());
        assertThat(detail.deliveryStatus()).isEqualTo("WITHHELD_PERMANENTLY");
        assertThat(detail.finalAnswer()).isNull();
        assertThat(item.getStatus()).isEqualTo(AiHeldItemStatus.REJECTED);
        verify(askAuditService).appendStandaloneEvent(
                eq(item.getAuditId()),
                eq(AiAskAuditService.HITL_REJECTED),
                eq(99L),
                argThat(payload ->
                        "REVIEWER_REJECTED".equals(payload.get("reasonCode"))
                                && Integer.valueOf(12).equals(payload.get("reasonLength"))
                                && !payload.containsKey("reason")));
        verify(askAuditService).recordHitlDeliverySupplement(
                eq(item.getAuditId()),
                eq("WITHHELD_PERMANENTLY"),
                isNull(),
                eq(42L),
                any(),
                eq(99L));
        verify(heldItemRepository).updateOutcomeIfStatus(
                eq(item.getId()),
                eq(AiHeldItemStatus.PENDING_REVIEW),
                eq(AiHeldItemStatus.REJECTED),
                eq("WITHHELD_PERMANENTLY"),
                isNull(),
                eq("[]"),
                eq(99L),
                any(),
                eq("unsafe claim"),
                any());
    }

    @Test
    @DisplayName("release on non-pending item conflicts")
    void release_nonPending_conflicts() {
        final AiHeldItem item = pendingItem();
        item.setStatus(AiHeldItemStatus.DELIVERED);
        item.setDeliveryStatus("DELIVERED");
        item.setFinalAnswer(item.getDraftAnswer());
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        assertThatThrownBy(() -> service.release(item.getId(), reviewer(), null, null))
                .isInstanceOf(HitlConflictException.class)
                .hasMessageContaining("not pending");
        verify(auditEventRepository, never()).save(any());
        verify(heldItemRepository, never()).updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any());
    }

    @Test
    @DisplayName("release conflicts when another writer already transitioned the row")
    void release_concurrentUpdate_conflicts() {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(heldItemRepository.updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(0);

        assertThatThrownBy(() -> service.release(item.getId(), reviewer(), null, null))
                .isInstanceOf(HitlConflictException.class)
                .hasMessageContaining("not pending");
        verify(auditEventRepository, never()).save(any());
    }

    @Test
    @DisplayName("release denies caregiver without patient link with uniform not-found")
    void release_unlinkedCaregiver_forbidden() {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(caregiverPatientLinkService.hasAccessToPatient(eq(99L), eq(7L))).thenReturn(false);

        assertThatThrownBy(() -> service.release(item.getId(), reviewer(), null, null))
                .isInstanceOf(HitlNotFoundException.class)
                .hasMessageContaining("not found");
        verify(heldItemRepository, never()).updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any());
    }

    @Test
    @DisplayName("listQueue filters to patients linked to the caregiver")
    void listQueue_filtersByPatientAccess() throws Exception {
        final AiHeldItem linked = pendingItem();
        final AiHeldItem otherLinked = pendingItem();
        otherLinked.setId(UUID.randomUUID());
        otherLinked.setPatientId(99L);
        stubLinkedPatient(99L, 88L);
        when(patientRepository.findIdsLinkedToCaregiver(eq(99L), any()))
                .thenReturn(List.of(42L));
        when(heldItemRepository.findByPatientIdInAndStatusOrderByCreatedAtAsc(
                eq(List.of(42L)), eq(AiHeldItemStatus.PENDING_REVIEW)))
                .thenReturn(List.of(linked));

        final List<HitlQueueItem> queue = service.listQueue(reviewer());

        assertThat(queue).hasSize(1);
        assertThat(queue.get(0).heldItemId()).isEqualTo(linked.getId());
        verify(heldItemRepository, never())
                .findByStatusOrderByCreatedAtAsc(any());
    }

    @Test
    @DisplayName("expireDueHolds transitions past-due pending rows")
    void expireDueHolds_expiresBatch() {
        final AiHeldItem item = pendingItem();
        item.setExpiresAt(Instant.now().minus(1, ChronoUnit.HOURS));
        when(heldItemRepository.findByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(
                eq(AiHeldItemStatus.PENDING_REVIEW), any(), any()))
                .thenReturn(List.of(item));
        when(heldItemRepository.expireIfPending(eq(item.getId()), any())).thenReturn(1);

        final int expired = service.expireDueHolds(50);

        assertThat(expired).isEqualTo(1);
        assertThat(item.getStatus()).isEqualTo(AiHeldItemStatus.EXPIRED);
        final ArgumentCaptor<AiSafetyAuditEvent> auditCaptor =
                ArgumentCaptor.forClass(AiSafetyAuditEvent.class);
        verify(auditEventRepository).save(auditCaptor.capture());
        assertThat(auditCaptor.getValue().getEventType()).isEqualTo("HITL_EXPIRED");
    }

    private void stubLinkedPatient(final long patientId, final long patientUserId) {
        final Patient patient = new Patient();
        patient.setId(patientId);
        final User patientUser = new User();
        patientUser.setId(patientUserId);
        patient.setUser(patientUser);
        org.mockito.Mockito.lenient()
                .when(patientRepository.findById(patientId))
                .thenReturn(Optional.of(patient));
    }

    private static SafetyInput safetyInput(final String query, final String draft) {
        return new SafetyInput(
                query,
                draft,
                List.of(),
                42L,
                7L,
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                "ASK_AI",
                "en-US",
                false,
                List.of());
    }

    private static AiHeldItem pendingItem() {
        final Instant now = Instant.now();
        return AiHeldItem.builder()
                .id(UUID.randomUUID())
                .patientId(42L)
                .requesterUserId(7L)
                .sessionId(UUID.randomUUID())
                .auditId(UUID.randomUUID())
                .requestId(UUID.randomUUID())
                .sourceSurface("ASK_AI")
                .status(AiHeldItemStatus.PENDING_REVIEW)
                .tier(2)
                .triggerCodesJson("[\"MEDICATION_CHANGE\"]")
                .queryText("Should I stop taking metformin?")
                .queryTextHash("abc")
                .draftAnswer("Draft answer text for review")
                .citationsJson("[]")
                .validationFindingsJson("[]")
                .deliveryStatus("HELD")
                .expiresAt(now.plus(72, ChronoUnit.HOURS))
                .createdAt(now)
                .updatedAt(now)
                .build();
    }

    private static User requester() {
        final User user = new User();
        user.setId(7L);
        user.setRole(Role.PATIENT);
        return user;
    }

    private static User reviewer() {
        final User user = new User();
        user.setId(99L);
        user.setRole(Role.CAREGIVER);
        return user;
    }

    @Test
    @DisplayName("findOpenHold returns match and rejects blank args")
    void findOpenHold_returnsMatchAndRejectsBlankArgs() {
        assertThat(service.findOpenHold(null, "ASK_AI", "key")).isEmpty();
        assertThat(service.findOpenHold(42L, " ", "key")).isEmpty();
        assertThat(service.findOpenHold(42L, "ASK_AI", "")).isEmpty();

        final AiHeldItem existing = pendingItem();
        when(heldItemRepository
                        .findFirstByPatientIdAndSourceSurfaceAndQueryTextHashAndStatusOrderByCreatedAtDesc(
                                eq(42L), eq("ASK_AI"), any(), eq(AiHeldItemStatus.PENDING_REVIEW)))
                .thenReturn(Optional.of(existing));

        assertThat(service.findOpenHold(42L, "ASK_AI", "stable-key")).contains(existing);
    }

    @Test
    @DisplayName("createHold reuses an existing open hold")
    void createHold_reusesExistingOpenHold() {
        final AiHeldItem existing = pendingItem();
        when(heldItemRepository
                        .findFirstByPatientIdAndSourceSurfaceAndQueryTextHashAndStatusOrderByCreatedAtDesc(
                                any(), any(), any(), eq(AiHeldItemStatus.PENDING_REVIEW)))
                .thenReturn(Optional.of(existing));

        final AiHeldItem result = service.createHold(
                new SafetyInput(
                        "q",
                        "draft",
                        List.of(),
                        42L,
                        7L,
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        "ASK_AI",
                        "en-US",
                        true,
                        List.of("X")),
                SafetyOutcome.holdTier2(List.of("X"), List.of()),
                List.of());

        assertThat(result).isSameAs(existing);
        verify(openHoldWriter, never()).insertOpenHold(any());
    }

    @Test
    @DisplayName("createHold rejects null patientId")
    void createHold_nullPatientId_throws() {
        assertThatThrownBy(() -> service.createHold(
                        new SafetyInput(
                                "q",
                                "draft",
                                List.of(),
                                null,
                                7L,
                                null,
                                null,
                                null,
                                "ASK_AI",
                                "en-US",
                                true,
                                List.of()),
                        SafetyOutcome.holdTier2(List.of(), List.of()),
                        List.of()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("patientId");
    }

    @Test
    @DisplayName("getStatus returns withheld message for REJECTED")
    void getStatus_rejected_withholdsMessage() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setStatus(AiHeldItemStatus.REJECTED);
        item.setDeliveryStatus("WITHHELD_PERMANENTLY");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.status()).isEqualTo(AiHeldItemStatus.REJECTED.name());
        assertThat(status.deliveryStatus()).isEqualTo("WITHHELD_PERMANENTLY");
        assertThat(status.message()).isEqualTo(HitlService.REJECTED_MESSAGE);
        assertThat(status.answer()).isNull();
    }

    @Test
    @DisplayName("getStatus allows admin without patient link")
    void getStatus_adminBypassesLinkCheck() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        final User admin = new User();
        admin.setId(1L);
        admin.setRole(Role.ADMIN);

        final HitlStatusResponse status = service.getStatus(item.getId(), admin);

        assertThat(status.status()).isEqualTo(AiHeldItemStatus.PENDING_REVIEW.name());
        verify(caregiverPatientLinkService, never()).hasAccessToPatient(anyLong(), anyLong());
    }

    @Test
    @DisplayName("getStatus allows family member with access")
    void getStatus_familyMemberWithAccess_allowed() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        final User family = new User();
        family.setId(88L);
        family.setRole(Role.FAMILY_MEMBER);
        when(familyMemberService.hasAccessToPatient(eq(88L), eq(7L))).thenReturn(true);

        final HitlStatusResponse status = service.getStatus(item.getId(), family);

        assertThat(status.status()).isEqualTo(AiHeldItemStatus.PENDING_REVIEW.name());
    }

    @Test
    @DisplayName("listQueue for admin returns all pending holds")
    void listQueue_adminSeesAllPending() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findByStatusOrderByCreatedAtAsc(AiHeldItemStatus.PENDING_REVIEW))
                .thenReturn(List.of(item));
        final User admin = new User();
        admin.setId(1L);
        admin.setRole(Role.ADMIN);

        final List<HitlQueueItem> queue = service.listQueue(admin);

        assertThat(queue).hasSize(1);
        assertThat(queue.get(0).heldItemId()).isEqualTo(item.getId());
    }

    @Test
    @DisplayName("reject with blank reason uses UNSPECIFIED")
    void reject_blankReason_usesUnspecified() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(heldItemRepository.updateOutcomeIfStatus(
                        any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(1);

        service.reject(item.getId(), reviewer(), "  ");

        verify(askAuditService).appendStandaloneEvent(
                eq(item.getAuditId()),
                eq(AiAskAuditService.HITL_REJECTED),
                eq(99L),
                argThat(payload -> "UNSPECIFIED".equals(payload.get("reasonCode"))));
    }

    @Test
    @DisplayName("getStatus for delivered returns answer and empty citations on bad JSON")
    void getStatus_delivered_withBadCitationsJson() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setStatus(AiHeldItemStatus.DELIVERED);
        item.setDeliveryStatus("DELIVERED");
        item.setFinalAnswer("Released answer");
        item.setCitationsJson("not-json");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.deliveryStatus()).isEqualTo("DELIVERED");
        assertThat(status.answer()).isEqualTo("Released answer");
        assertThat(status.citations()).isEmpty();
    }

    @Test
    @DisplayName("getStatus rejects null caller")
    void getStatus_nullCaller_unauthorized() {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        assertThatThrownBy(() -> service.getStatus(item.getId(), null))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    @DisplayName("listQueue returns empty when caregiver has no linked patients")
    void listQueue_caregiverWithNoLinks_empty() throws Exception {
        when(patientRepository.findIdsLinkedToCaregiver(eq(99L), any()))
                .thenReturn(List.of());

        assertThat(service.listQueue(reviewer())).isEmpty();
    }

    @Test
    @DisplayName("createHold truncates long query and defaults null draft/citations")
    void createHold_truncatesLongQueryAndDefaults() {
        when(heldItemRepository
                        .findFirstByPatientIdAndSourceSurfaceAndQueryTextHashAndStatusOrderByCreatedAtDesc(
                                any(), any(), any(), eq(AiHeldItemStatus.PENDING_REVIEW)))
                .thenReturn(Optional.empty());
        when(openHoldWriter.insertOpenHold(any())).thenAnswer(inv -> inv.getArgument(0));

        final String longQuery = "Q".repeat(2500);
        final AiHeldItem saved = service.createHold(
                new SafetyInput(
                        longQuery,
                        null,
                        null,
                        42L,
                        7L,
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        null,
                        "en-US",
                        true,
                        List.of("X")),
                SafetyOutcome.holdTier2(List.of("X"), List.of()),
                null);

        assertThat(saved.getQueryText()).hasSize(2000);
        assertThat(saved.getDraftAnswer()).isEmpty();
        assertThat(saved.getSourceSurface()).isEqualTo("ASK_AI");
        assertThat(saved.getCitationsJson()).isEqualTo("[]");
    }

    @Test
    @DisplayName("expire skips Ask AI ledger when auditId is null")
    void getStatus_expireWithNullAuditId_skipsLedger() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setAuditId(null);
        item.setExpiresAt(Instant.now().minus(1, ChronoUnit.HOURS));
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(heldItemRepository.expireIfPending(eq(item.getId()), any())).thenReturn(1);

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.status()).isEqualTo(AiHeldItemStatus.EXPIRED.name());
        verify(askAuditService, never()).appendStandaloneEvent(any(), any(), any(), any());
    }

    @Test
    @DisplayName("reject on non-pending item conflicts")
    void reject_nonPending_conflicts() {
        final AiHeldItem item = pendingItem();
        item.setStatus(AiHeldItemStatus.REJECTED);
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        assertThatThrownBy(() -> service.reject(item.getId(), reviewer(), "late"))
                .isInstanceOf(HitlConflictException.class);
    }

    @Test
    @DisplayName("reject rejects non-reviewer roles")
    void reject_patientRole_unauthorized() {
        assertThatThrownBy(() -> service.reject(UUID.randomUUID(), requester(), "nope"))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Reviewer");
    }

    @Test
    @DisplayName("getStatus APPROVED_AS_IS falls back to draft answer")
    void getStatus_approvedAsIs_usesDraft() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setStatus(AiHeldItemStatus.APPROVED_AS_IS);
        item.setDeliveryStatus("DELIVERED");
        item.setFinalAnswer(null);
        item.setDraftAnswer("Draft kept");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.deliveryStatus()).isEqualTo("DELIVERED");
        assertThat(status.answer()).isEqualTo("Draft kept");
    }

    @Test
    @DisplayName("createHold blank query stores null query text")
    void createHold_blankQuery_nullQueryText() {
        when(heldItemRepository
                        .findFirstByPatientIdAndSourceSurfaceAndQueryTextHashAndStatusOrderByCreatedAtDesc(
                                any(), any(), any(), eq(AiHeldItemStatus.PENDING_REVIEW)))
                .thenReturn(Optional.empty());
        when(openHoldWriter.insertOpenHold(any())).thenAnswer(inv -> inv.getArgument(0));

        final AiHeldItem saved = service.createHold(
                new SafetyInput(
                        "   ",
                        "draft",
                        List.of(),
                        42L,
                        7L,
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        "ASK_AI",
                        "en-US",
                        true,
                        List.of()),
                SafetyOutcome.holdTier2(List.of(), List.of()),
                List.of());

        assertThat(saved.getQueryText()).isNull();
    }

    @Test
    @DisplayName("listQueue truncates long query previews")
    void listQueue_longQuery_previewTruncated() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setQueryText("P".repeat(200));
        when(heldItemRepository.findByStatusOrderByCreatedAtAsc(AiHeldItemStatus.PENDING_REVIEW))
                .thenReturn(List.of(item));
        final User admin = new User();
        admin.setId(1L);
        admin.setRole(Role.ADMIN);

        final List<HitlQueueItem> queue = service.listQueue(admin);

        assertThat(queue.get(0).queryPreview()).hasSize(120);
    }

    @Test
    @DisplayName("reject truncates very long review notes")
    void reject_longReason_truncatesNotes() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(heldItemRepository.updateOutcomeIfStatus(
                        any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(1);

        service.reject(item.getId(), reviewer(), "N".repeat(600));

        final ArgumentCaptor<String> notes = ArgumentCaptor.forClass(String.class);
        verify(heldItemRepository).updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), any(), anyLong(), any(), notes.capture(), any());
        assertThat(notes.getValue()).hasSize(500);
    }

    @Test
    @DisplayName("getStatus blank citations JSON returns empty list")
    void getStatus_blankCitationsJson_emptyList() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setStatus(AiHeldItemStatus.DELIVERED);
        item.setDeliveryStatus("DELIVERED");
        item.setFinalAnswer("ok");
        item.setCitationsJson("   ");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlStatusResponse status = service.getStatus(item.getId(), requester());

        assertThat(status.citations()).isEmpty();
    }

    @Test
    @DisplayName("listQueue blank query preview is null")
    void listQueue_blankQuery_previewNull() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setQueryText("  ");
        when(heldItemRepository.findByStatusOrderByCreatedAtAsc(AiHeldItemStatus.PENDING_REVIEW))
                .thenReturn(List.of(item));
        final User admin = new User();
        admin.setId(1L);
        admin.setRole(Role.ADMIN);

        final List<HitlQueueItem> queue = service.listQueue(admin);

        assertThat(queue.get(0).queryPreview()).isNull();
    }

    @Test
    @DisplayName("release by admin bypasses caregiver link check")
    void release_adminBypassesPatientLink() throws Exception {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(heldItemRepository.updateOutcomeIfStatus(
                        any(), any(), any(), any(), any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(1);
        final User admin = new User();
        admin.setId(1L);
        admin.setRole(Role.ADMIN);

        final HitlDetailResponse detail = service.release(item.getId(), admin, null, null);

        assertThat(detail.deliveryStatus()).isEqualTo("DELIVERED");
        verify(caregiverPatientLinkService, never()).hasAccessToPatient(anyLong(), anyLong());
    }
}
