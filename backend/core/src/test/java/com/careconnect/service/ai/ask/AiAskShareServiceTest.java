package com.careconnect.service.ai.ask;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.ai.AiAskShareRequest;
import com.careconnect.dto.ai.AiAskShareResponse;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ai.ask.AiAskConversationShare;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ai.ask.AiAskConversationShareRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ChatAuditService;
import com.careconnect.service.ai.retrieval.CaregiverVisibilityFilter;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.retrieval.RetrievalScope;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AiAskShareServiceTest {

    @Mock private RetrievalScopeService retrievalScopeService;
    @Mock private PatientRepository patientRepository;
    @Mock private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock private AiAskConversationShareRepository shareRepository;
    @Mock private ChatAuditService chatAuditService;

    private AiAskShareService service;

    @BeforeEach
    void setUp() {
        service = new AiAskShareService(
                retrievalScopeService,
                patientRepository,
                caregiverPatientLinkService,
                shareRepository,
                chatAuditService,
                new ObjectMapper());
        lenient()
                .when(shareRepository.findFirstByPatientIdAndSharedByUserIdAndTranscriptSha256OrderByCreatedAtDesc(
                        any(), any(), anyString()))
                .thenReturn(Optional.empty());
    }

    @Test
    void share_persistsTranscriptAndRecipients() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L))
                .thenReturn(List.of(link(11L), link(12L)));
        when(shareRepository.save(any(AiAskConversationShare.class))).thenAnswer(inv -> {
            final AiAskConversationShare share = inv.getArgument(0);
            if (share.getCreatedAt() == null) {
                share.setCreatedAt(java.time.Instant.parse("2026-07-27T12:00:00Z"));
            }
            return share;
        });

        final UUID sessionId = UUID.fromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        final AiAskShareResponse response = service.share(
                caller,
                new AiAskShareRequest(
                        7L,
                        sessionId,
                        null,
                        List.of(
                                new AiAskShareRequest.AiAskShareMessage(
                                        "user", "What meds am I on?", "2026-07-27T12:00:00Z"),
                                new AiAskShareRequest.AiAskShareMessage(
                                        "assistant", "Metformin 500mg.", "2026-07-27T12:00:01Z"))));

        assertThat(response.patientId()).isEqualTo(7L);
        assertThat(response.sessionId()).isEqualTo(sessionId);
        assertThat(response.recipientUserIds()).containsExactly(11L, 12L);
        assertThat(response.messageCount()).isEqualTo(2);

        final ArgumentCaptor<AiAskConversationShare> captor =
                ArgumentCaptor.forClass(AiAskConversationShare.class);
        verify(shareRepository).save(captor.capture());
        assertThat(captor.getValue().getTranscriptJson()).contains("Metformin");
        assertThat(captor.getValue().getRecipientUserIds()).contains("11");
        verify(chatAuditService).logConversationShared(eq(9L), anyString(), eq(11L));
        verify(chatAuditService).logConversationShared(eq(9L), anyString(), eq(12L));
    }

    @Test
    void share_rejectsUnlinkedProvider() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L))
                .thenReturn(List.of(link(11L)));

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                99L,
                                List.of(new AiAskShareRequest.AiAskShareMessage(
                                        "user", "hi", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("CAREGIVER_NOT_LINKED");
    }

    @Test
    void share_withSpecificLinkedProvider_usesOnlyThatRecipient() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L))
                .thenReturn(List.of(link(11L), link(12L)));
        when(shareRepository.save(any(AiAskConversationShare.class))).thenAnswer(inv -> {
            final AiAskConversationShare share = inv.getArgument(0);
            share.setCreatedAt(java.time.Instant.parse("2026-07-27T12:00:00Z"));
            return share;
        });

        final AiAskShareResponse response = service.share(
                caller,
                new AiAskShareRequest(
                        7L,
                        null,
                        12L,
                        List.of(new AiAskShareRequest.AiAskShareMessage(
                                "USER", "Hello provider", "2026-07-27T12:00:00Z"))));

        assertThat(response.recipientUserIds()).containsExactly(12L);
        verify(chatAuditService).logConversationShared(eq(9L), anyString(), eq(12L));
        verify(chatAuditService, never()).logConversationShared(eq(9L), anyString(), eq(11L));
    }

    @Test
    void share_rejectsNullCallerAndMissingPatient() throws Exception {
        assertThatThrownBy(() -> service.share(
                        null,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage("user", "hi", null)))))
                .isInstanceOf(com.careconnect.security.UnauthorizedException.class);

        final User caller = user(9L, Role.PATIENT);
        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage("user", "hi", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("PATIENT_NOT_FOUND");
    }

    @Test
    void share_rejectsBlankMessagesAndMissingPatientUser() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of(link(11L)));

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage("user", "  ", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("INVALID_REQUEST");

        final Patient missingUser = new Patient();
        missingUser.setId(7L);
        missingUser.setUser(null);
        when(patientRepository.findById(7L)).thenReturn(Optional.of(missingUser));

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage("user", "hi", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("PATIENT_NOT_FOUND");
    }

    @Test
    void share_rejectsWhenNoLinkedCaregivers() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of());

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage(
                                        "user", "hi", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("NO_CAREGIVER");
    }

    @Test
    void share_rejectsMissingPatientIdAndEmptyMessages() {
        final User caller = user(9L, Role.PATIENT);

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(null, null, null, List.of(
                                new AiAskShareRequest.AiAskShareMessage("user", "hi", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("INVALID_REQUEST");

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(7L, null, null, List.of())))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("INVALID_REQUEST");
    }

    @Test
    void share_rejectsOversizedTranscript() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of(link(11L)));

        final String huge = "x".repeat(200_001);
        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage("user", huge, null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("TRANSCRIPT_TOO_LARGE");
    }

    @Test
    void share_normalizesRolesAndContinuesWhenAuditFails() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of(link(11L)));
        when(shareRepository.save(any(AiAskConversationShare.class))).thenAnswer(inv -> {
            final AiAskConversationShare share = inv.getArgument(0);
            share.setCreatedAt(java.time.Instant.parse("2026-07-27T12:00:00Z"));
            return share;
        });
        doThrow(new RuntimeException("audit down"))
                .when(chatAuditService)
                .logConversationShared(any(), anyString(), any());

        final List<AiAskShareRequest.AiAskShareMessage> messages = new java.util.ArrayList<>();
        messages.add(new AiAskShareRequest.AiAskShareMessage(null, "Hello", "  "));
        messages.add(new AiAskShareRequest.AiAskShareMessage("SYSTEM", "Note", "t"));
        messages.add(new AiAskShareRequest.AiAskShareMessage("other", "Fallback", null));
        messages.add(null);

        final AiAskShareResponse response = service.share(
                caller,
                new AiAskShareRequest(7L, null, null, messages));

        assertThat(response.recipientUserIds()).containsExactly(11L);
        final ArgumentCaptor<AiAskConversationShare> captor =
                ArgumentCaptor.forClass(AiAskConversationShare.class);
        verify(shareRepository).save(captor.capture());
        assertThat(captor.getValue().getTranscriptJson())
                .contains("\"role\":\"assistant\"")
                .contains("\"role\":\"system\"");
    }

    @Test
    void share_rejectsWhenRecipientSerializationFails() throws Exception {
        final ObjectMapper failingMapper = mock(ObjectMapper.class);
        when(failingMapper.writeValueAsString(any())).thenAnswer(inv -> {
            final Object arg = inv.getArgument(0);
            if (arg instanceof List<?> list && !list.isEmpty() && list.get(0) instanceof Long) {
                throw new JsonProcessingException("boom") {};
            }
            return new ObjectMapper().writeValueAsString(arg);
        });
        service = new AiAskShareService(
                retrievalScopeService,
                patientRepository,
                caregiverPatientLinkService,
                shareRepository,
                chatAuditService,
                failingMapper);

        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of(link(11L)));

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage(
                                        "user", "hi", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("INTERNAL_ERROR");
    }

    @Test
    void share_rejectsWhenTranscriptSerializationFails() throws Exception {
        final ObjectMapper failingMapper = mock(ObjectMapper.class);
        when(failingMapper.writeValueAsString(any())).thenThrow(new JsonProcessingException("boom") {});
        service = new AiAskShareService(
                retrievalScopeService,
                patientRepository,
                caregiverPatientLinkService,
                shareRepository,
                chatAuditService,
                failingMapper);

        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of(link(11L)));

        assertThatThrownBy(() -> service.share(
                        caller,
                        new AiAskShareRequest(
                                7L,
                                null,
                                null,
                                List.of(new AiAskShareRequest.AiAskShareMessage(
                                        "user", "hi", null)))))
                .isInstanceOf(AskAiRejectedException.class)
                .extracting(ex -> ((AskAiRejectedException) ex).getErrorCode())
                .isEqualTo("INTERNAL_ERROR");
    }

    @Test
    void share_returnsExistingShareOnDuplicateTranscript() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        final UUID existingId = UUID.fromString("11111111-1111-1111-1111-111111111111");
        final AiAskConversationShare existing = AiAskConversationShare.builder()
                .id(existingId)
                .patientId(7L)
                .sharedByUserId(9L)
                .messageCount(1)
                .recipientUserIds("[11]")
                .transcriptJson("[{\"role\":\"user\",\"text\":\"hi\"}]")
                .transcriptSha256("abc")
                .createdAt(java.time.Instant.parse("2026-07-27T11:00:00Z"))
                .build();

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of(link(11L), link(99L)));
        when(shareRepository.findFirstByPatientIdAndSharedByUserIdAndTranscriptSha256OrderByCreatedAtDesc(
                        any(), any(), anyString()))
                .thenReturn(Optional.of(existing));

        final AiAskShareResponse response = service.share(
                caller,
                new AiAskShareRequest(
                        7L,
                        null,
                        null,
                        List.of(new AiAskShareRequest.AiAskShareMessage("user", "hi", null))));

        assertThat(response.shareId()).isEqualTo(existingId);
        assertThat(response.messageCount()).isEqualTo(1);
        assertThat(response.recipientUserIds()).containsExactly(11L);
        verify(shareRepository, never()).save(any());
        verify(chatAuditService, never()).logConversationShared(any(), anyString(), any());
    }

    @Test
    void listShares_returnsPatientSharesAfterScopeCheck() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(shareRepository.findByPatientIdOrderByCreatedAtDesc(7L)).thenReturn(List.of(
                AiAskConversationShare.builder()
                        .id(UUID.fromString("11111111-1111-1111-1111-111111111111"))
                        .patientId(7L)
                        .sharedByUserId(9L)
                        .messageCount(2)
                        .recipientUserIds("[11,12]")
                        .transcriptJson("[]")
                        .transcriptSha256("x")
                        .createdAt(java.time.Instant.parse("2026-07-27T12:00:00Z"))
                        .build()));

        final var responses = service.listShares(caller, 7L);

        assertThat(responses).hasSize(1);
        assertThat(responses.get(0).recipientUserIds()).containsExactly(11L, 12L);
        assertThat(responses.get(0).messageCount()).isEqualTo(2);
    }

    @Test
    void share_messageCountMatchesPersistedTranscriptRows() throws Exception {
        final User caller = user(9L, Role.PATIENT);
        final User patientUser = user(42L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(7L);
        patient.setUser(patientUser);

        when(retrievalScopeService.resolveRetrievalScope(caller, 7L)).thenReturn(scope(9L));
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));
        when(caregiverPatientLinkService.getCaregiversByPatient(42L)).thenReturn(List.of(link(11L)));
        when(shareRepository.save(any(AiAskConversationShare.class))).thenAnswer(inv -> {
            final AiAskConversationShare share = inv.getArgument(0);
            share.setCreatedAt(java.time.Instant.parse("2026-07-27T12:00:00Z"));
            return share;
        });

        final List<AiAskShareRequest.AiAskShareMessage> messages = new java.util.ArrayList<>();
        messages.add(new AiAskShareRequest.AiAskShareMessage("user", "keep me", null));
        messages.add(null);

        final AiAskShareResponse response = service.share(
                caller, new AiAskShareRequest(7L, null, null, messages));

        assertThat(response.messageCount()).isEqualTo(1);
        final ArgumentCaptor<AiAskConversationShare> captor =
                ArgumentCaptor.forClass(AiAskConversationShare.class);
        verify(shareRepository).save(captor.capture());
        assertThat(captor.getValue().getMessageCount()).isEqualTo(1);
    }

    private static RetrievalScope scope(final long callerUserId) {
        return new RetrievalScope(
                callerUserId,
                Role.PATIENT,
                Set.of(7L),
                EnumSet.noneOf(RetrievalRecordType.class),
                EnumSet.noneOf(RetrievalRecordType.class),
                new CaregiverVisibilityFilter(Role.PATIENT, true),
                true);
    }

    private static User user(final long id, final Role role) {
        final User user = new User();
        user.setId(id);
        user.setRole(role);
        return user;
    }

    private static CaregiverPatientLinkResponse link(final long caregiverUserId) {
        return new CaregiverPatientLinkResponse(
                1L,
                caregiverUserId,
                "Caregiver",
                "c@example.com",
                42L,
                "Patient",
                "p@example.com",
                "ACTIVE",
                "PRIMARY",
                true,
                true,
                LocalDateTime.now(),
                null,
                null,
                "system",
                true,
                false);
    }
}
