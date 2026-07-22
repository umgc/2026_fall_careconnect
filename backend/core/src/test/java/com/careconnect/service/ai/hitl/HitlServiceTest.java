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
import com.careconnect.service.ai.safety.SafetyInput;
import com.careconnect.service.ai.safety.SafetyOutcome;
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
    private PatientRepository patientRepository;
    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock
    private FamilyMemberService familyMemberService;

    private HitlService service;

    @BeforeEach
    void setUp() {
        service = new HitlService(
                heldItemRepository,
                auditEventRepository,
                patientRepository,
                caregiverPatientLinkService,
                familyMemberService,
                new ObjectMapper(),
                72L);
        org.mockito.Mockito.lenient().when(heldItemRepository.save(any(AiHeldItem.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        org.mockito.Mockito.lenient().when(auditEventRepository.save(any(AiSafetyAuditEvent.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        stubLinkedPatient(42L, 7L);
        org.mockito.Mockito.lenient()
                .when(caregiverPatientLinkService.hasAccessToPatient(eq(99L), eq(7L)))
                .thenReturn(true);
        org.mockito.Mockito.lenient()
                .when(heldItemRepository.updateOutcomeIfStatus(
                        any(), any(), any(), any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(1);
        org.mockito.Mockito.lenient()
                .when(heldItemRepository.expireIfPending(any(), any()))
                .thenReturn(1);
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
        when(heldItemRepository.findByStatusOrderByCreatedAtAsc(AiHeldItemStatus.PENDING_REVIEW))
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
        verify(heldItemRepository).updateOutcomeIfStatus(
                eq(item.getId()),
                eq(AiHeldItemStatus.PENDING_REVIEW),
                eq(AiHeldItemStatus.DELIVERED),
                eq("DELIVERED"),
                eq(item.getDraftAnswer()),
                eq(99L),
                any(),
                eq("looks good"),
                any());
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
                any(), any(), any(), any(), any(), anyLong(), any(), any(), any());
    }

    @Test
    @DisplayName("UNSUPPORTED_CLAIM hold releases when reviewer provides an edited answer")
    void release_unsupportedClaim_withEdit_succeeds() throws Exception {
        final AiHeldItem item = pendingItem();
        item.setTriggerCodesJson("[\"UNSUPPORTED_CLAIM\"]");
        item.setDraftAnswer("Partial verified draft");
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));

        final HitlDetailResponse detail = service.release(
                item.getId(), reviewer(), "Clinician-approved rewritten answer", "fixed");

        assertThat(detail.deliveryStatus()).isEqualTo("DELIVERED");
        assertThat(detail.finalAnswer()).isEqualTo("Clinician-approved rewritten answer");
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
        verify(heldItemRepository).updateOutcomeIfStatus(
                eq(item.getId()),
                eq(AiHeldItemStatus.PENDING_REVIEW),
                eq(AiHeldItemStatus.REJECTED),
                eq("WITHHELD_PERMANENTLY"),
                isNull(),
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
                any(), any(), any(), any(), any(), anyLong(), any(), any(), any());
    }

    @Test
    @DisplayName("release conflicts when another writer already transitioned the row")
    void release_concurrentUpdate_conflicts() {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(heldItemRepository.updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), anyLong(), any(), any(), any()))
                .thenReturn(0);

        assertThatThrownBy(() -> service.release(item.getId(), reviewer(), null, null))
                .isInstanceOf(HitlConflictException.class)
                .hasMessageContaining("not pending");
        verify(auditEventRepository, never()).save(any());
    }

    @Test
    @DisplayName("release denies caregiver without patient link")
    void release_unlinkedCaregiver_forbidden() {
        final AiHeldItem item = pendingItem();
        when(heldItemRepository.findById(item.getId())).thenReturn(Optional.of(item));
        when(caregiverPatientLinkService.hasAccessToPatient(eq(99L), eq(7L))).thenReturn(false);

        assertThatThrownBy(() -> service.release(item.getId(), reviewer(), null, null))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("patient");
        verify(heldItemRepository, never()).updateOutcomeIfStatus(
                any(), any(), any(), any(), any(), anyLong(), any(), any(), any());
    }

    @Test
    @DisplayName("listQueue filters to patients linked to the caregiver")
    void listQueue_filtersByPatientAccess() throws Exception {
        final AiHeldItem linked = pendingItem();
        final AiHeldItem unlinked = pendingItem();
        unlinked.setId(UUID.randomUUID());
        unlinked.setPatientId(99L);
        stubLinkedPatient(99L, 88L);
        when(heldItemRepository.findByStatusOrderByCreatedAtAsc(AiHeldItemStatus.PENDING_REVIEW))
                .thenReturn(List.of(linked, unlinked));
        when(caregiverPatientLinkService.hasAccessToPatient(eq(99L), eq(7L))).thenReturn(true);
        when(caregiverPatientLinkService.hasAccessToPatient(eq(99L), eq(88L))).thenReturn(false);

        final List<HitlQueueItem> queue = service.listQueue(reviewer());

        assertThat(queue).hasSize(1);
        assertThat(queue.get(0).heldItemId()).isEqualTo(linked.getId());
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
}
