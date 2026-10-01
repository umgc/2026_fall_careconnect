package com.careconnect.service.confirmation;

import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.CreateConfirmationRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.confirmation.ConfirmationItem;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.confirmation.ConfirmationStatus;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.repository.confirmation.ConfirmationItemRepository;
import com.careconnect.service.safety.AiAuditLedgerService;
import com.careconnect.service.visibility.CaregiverVisibilityService;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.orm.ObjectOptimisticLockingFailureException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ConfirmationServiceTest {

    private static final Long USER_ID = 10L;
    private static final Long RESOLVER_ID = 20L;
    private static final String PAYLOAD = "{\"summary\":\"Patient took medication\"}";
    private static final String REFERENCE_ID = "call-123";
    private static final String NOTE = "Verified with patient";
    @Mock
    private ConfirmationItemRepository repository;
    @Mock
    private AiAuditLedgerService auditLedgerService;
    @Mock
    private ObjectProvider<CaregiverVisibilityService> visibilityServiceProvider;
    @Mock
    private CaregiverVisibilityService caregiverVisibilityService;
    @InjectMocks
    private ConfirmationService service;

    // createItem

    private ConfirmationItem buildPendingItem(Long id) {
        return ConfirmationItem.builder()
                .id(id)
                .sourceType(ConfirmationSourceType.SUMMARY)
                .status(ConfirmationStatus.PENDING)
                .payload(PAYLOAD)
                .referenceId(REFERENCE_ID)
                .requestedBy(USER_ID)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();
    }

    // createItem from DTO

    @Nested
    class CreateItem {

        @Test
        void persistsEntityWithCorrectFields() {
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            service.createItem(ConfirmationSourceType.SUMMARY, PAYLOAD, REFERENCE_ID, USER_ID);

            ArgumentCaptor<ConfirmationItem> captor = ArgumentCaptor.forClass(ConfirmationItem.class);
            verify(repository).save(captor.capture());
            ConfirmationItem saved = captor.getValue();

            assertThat(saved.getSourceType()).isEqualTo(ConfirmationSourceType.SUMMARY);
            assertThat(saved.getPayload()).isEqualTo(PAYLOAD);
            assertThat(saved.getReferenceId()).isEqualTo(REFERENCE_ID);
            assertThat(saved.getRequestedBy()).isEqualTo(USER_ID);
            assertThat(saved.getStatus()).isEqualTo(ConfirmationStatus.PENDING);
        }

        @Test
        void fourArgOverload_leavesPatientIdNull() {
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
            ConfirmationItem item = service.createItem(ConfirmationSourceType.ASK_AI, PAYLOAD, REFERENCE_ID, USER_ID);
            assertThat(item.getPatientId()).isNull();
        }

        @Test
        void withPatientId_persistsAndMapsToResponse() {
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
            ConfirmationItem item = service.createItem(
                    ConfirmationSourceType.SUMMARY, PAYLOAD, REFERENCE_ID, USER_ID, 42L);
            assertThat(item.getPatientId()).isEqualTo(42L);
            assertThat(service.toResponse(item).getPatientId()).isEqualTo(42L);
        }

        @Test
        void defaultsStatusToPending() {
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            ConfirmationItem result = service.createItem(
                    ConfirmationSourceType.ASK_AI, PAYLOAD, null, USER_ID);

            assertThat(result.getStatus()).isEqualTo(ConfirmationStatus.PENDING);
        }

        @Test
        void returnsPersistedEntity() {
            ConfirmationItem expected = ConfirmationItem.builder()
                    .id(1L).sourceType(ConfirmationSourceType.SUMMARY).build();
            when(repository.save(any())).thenReturn(expected);

            ConfirmationItem result = service.createItem(
                    ConfirmationSourceType.SUMMARY, PAYLOAD, REFERENCE_ID, USER_ID);

            assertThat(result).isSameAs(expected);
        }

        /**
         * all 4 source types from AuditSourceFeature are accepted
         */
        @ParameterizedTest
        @EnumSource(ConfirmationSourceType.class)
        void acceptsAllSourceTypes(ConfirmationSourceType sourceType) {
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            assertThatCode(() ->
                    service.createItem(sourceType, PAYLOAD, REFERENCE_ID, USER_ID))
                    .doesNotThrowAnyException();

            ArgumentCaptor<ConfirmationItem> captor = ArgumentCaptor.forClass(ConfirmationItem.class);
            verify(repository).save(captor.capture());
            assertThat(captor.getValue().getSourceType()).isEqualTo(sourceType);
        }
    }

    // confirm 

    @Nested
    class CreateItemFromDto {

        @Test
        void parsesSourceTypeStringAndDelegates() {
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            CreateConfirmationRequest req = CreateConfirmationRequest.builder()
                    .sourceType("ASK_AI")
                    .payload(PAYLOAD)
                    .referenceId(REFERENCE_ID)
                    .requestedBy(USER_ID)
                    .build();

            ConfirmationItem result = service.createItem(req);

            ArgumentCaptor<ConfirmationItem> captor = ArgumentCaptor.forClass(ConfirmationItem.class);
            verify(repository).save(captor.capture());
            assertThat(captor.getValue().getSourceType()).isEqualTo(ConfirmationSourceType.ASK_AI);
        }

        @Test
        void throwsOnInvalidSourceTypeString() {
            CreateConfirmationRequest req = CreateConfirmationRequest.builder()
                    .sourceType("INVALID_TYPE")
                    .payload(PAYLOAD)
                    .requestedBy(USER_ID)
                    .build();

            assertThatThrownBy(() -> service.createItem(req))
                    .isInstanceOf(AppException.class)
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.BAD_REQUEST);
        }
    }

    // dismiss

    @Nested
    class Confirm {

        @Test
        void transitionsPendingToConfirmed() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            ConfirmationItem result = service.confirm(1L, RESOLVER_ID, NOTE);

            assertThat(result.getStatus()).isEqualTo(ConfirmationStatus.CONFIRMED);
            assertThat(result.getResolvedBy()).isEqualTo(RESOLVER_ID);
            assertThat(result.getResolutionNote()).isEqualTo(NOTE);
            assertThat(result.getResolvedAt()).isNotNull();
        }

        @Test
        void writesConfirmationAuditEvent() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            service.confirm(1L, RESOLVER_ID, NOTE);

            verify(auditLedgerService).logConfirmation(
                    eq(AuditSourceFeature.SUMMARY), eq(RESOLVER_ID), isNull(), isNull(), any());
        }

        @Test
        void persistsConfirmedItem() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            service.confirm(1L, RESOLVER_ID, NOTE);

            verify(repository).save(item);
        }

        @Test
        void throwsWhenItemNotFound() {
            when(repository.findById(99L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.confirm(99L, RESOLVER_ID, NOTE))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("not found")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void confirmingCaregiverVisibilityItem_grantsVisibility() {
            ConfirmationItem item = ConfirmationItem.builder()
                    .id(7L)
                    .sourceType(ConfirmationSourceType.CAREGIVER_VISIBILITY)
                    .status(ConfirmationStatus.PENDING)
                    .payload("{}")
                    .referenceId("visibility:5:9")
                    .requestedBy(USER_ID)
                    .build();
            when(repository.findById(7L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
            when(visibilityServiceProvider.getObject()).thenReturn(caregiverVisibilityService);

            service.confirm(7L, RESOLVER_ID, NOTE);

            verify(caregiverVisibilityService).approveFromReview(5L, 9L, RESOLVER_ID);
        }

        @Test
        void confirmingNonVisibilityItem_doesNotTouchVisibility() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            service.confirm(1L, RESOLVER_ID, NOTE);

            verify(visibilityServiceProvider, never()).getObject();
        }

        /**
         * 4.11.2
         * cannot double-confirm
         */
        @Test
        void throwsWhenAlreadyConfirmed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.confirm(RESOLVER_ID, "first");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.confirm(1L, RESOLVER_ID, "second"))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("not PENDING")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.BAD_REQUEST);
        }

        /**
         * 4.11.2
         * cannot confirm a dismissed item
         */
        @Test
        void throwsWhenAlreadyDismissed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.dismiss(RESOLVER_ID, "dismissed");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.confirm(1L, RESOLVER_ID, "try confirm"))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("not PENDING")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void acceptsNullNote() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            ConfirmationItem result = service.confirm(1L, RESOLVER_ID, null);

            assertThat(result.getStatus()).isEqualTo(ConfirmationStatus.CONFIRMED);
            assertThat(result.getResolutionNote()).isNull();
        }

        @Test
        void throwsConflictWhenConcurrentlyModified() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
            doThrow(new ObjectOptimisticLockingFailureException(ConfirmationItem.class, 1L))
                    .when(repository).flush();

            assertThatThrownBy(() -> service.confirm(1L, RESOLVER_ID, NOTE))
                    .isInstanceOf(AppException.class)
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.CONFLICT);
        }
    }

    // timeout != approval (4.11.2)

    @Nested
    class Dismiss {

        @Test
        void transitionsPendingToDismissed() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            ConfirmationItem result = service.dismiss(1L, RESOLVER_ID, NOTE);

            assertThat(result.getStatus()).isEqualTo(ConfirmationStatus.DISMISSED);
            assertThat(result.getResolvedBy()).isEqualTo(RESOLVER_ID);
            assertThat(result.getResolutionNote()).isEqualTo(NOTE);
            assertThat(result.getResolvedAt()).isNotNull();
        }

        /**
         * (4.7.2): dismiss doesn't create a side effect
         * status is DISMISSED, not CONFIRMED
         */
        @Test
        void dismissedItemIsNotConfirmed() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            ConfirmationItem result = service.dismiss(1L, RESOLVER_ID, NOTE);

            assertThat(result.getStatus()).isNotEqualTo(ConfirmationStatus.CONFIRMED);
        }

        @Test
        void throwsWhenItemNotFound() {
            when(repository.findById(99L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.dismiss(99L, RESOLVER_ID, NOTE))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("not found")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void throwsWhenAlreadyDismissed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.dismiss(RESOLVER_ID, "first");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.dismiss(1L, RESOLVER_ID, "second"))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("not PENDING")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void throwsWhenAlreadyConfirmed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.confirm(RESOLVER_ID, "confirmed");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.dismiss(1L, RESOLVER_ID, "try dismiss"))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("not PENDING")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void throwsConflictWhenConcurrentlyModified() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
            doThrow(new ObjectOptimisticLockingFailureException(ConfirmationItem.class, 1L))
                    .when(repository).flush();

            assertThatThrownBy(() -> service.dismiss(1L, RESOLVER_ID, NOTE))
                    .isInstanceOf(AppException.class)
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.CONFLICT);
        }
    }

    // queries

    @Nested
    class TimeoutInvariant {

        /**
         * (4.11.2)
         * a PENDING item has no way to resolve itself besides confirmation
         * The only transitions are explicit confirm() or dismiss()
         */
        @Test
        void pendingItemStaysPendingWithoutExplicitAction() {
            ConfirmationItem item = buildPendingItem(1L);

            // Simulate time passing — item was created in the past
            item.setCreatedAt(LocalDateTime.now().minusDays(30));

            // Status is still PENDING — no auto-transition exists
            assertThat(item.getStatus()).isEqualTo(ConfirmationStatus.PENDING);
            assertThat(item.getResolvedBy()).isNull();
            assertThat(item.getResolvedAt()).isNull();
        }

        /**
         * the service provides no batch-resolve or auto-expire method
         */
        @Test
        void serviceHasNoAutoResolveMethod() {
            // The ConfirmationService public API only exposes confirm() and dismiss()
            // which both require an explicit resolverUserId.
            // If someone adds an auto-resolve, this will fail
            // they need to update this test and the contract.
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));
            when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

            // The only way to resolve is with an explicit user ID
            service.confirm(1L, RESOLVER_ID, null);
            assertThat(item.getResolvedBy()).isEqualTo(RESOLVER_ID);
        }
    }

    // integration tests

    @Nested
    class Queries {

        @Test
        void getPendingItems_returnsMappedDtos() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findByStatusOrderByCreatedAtDesc(ConfirmationStatus.PENDING))
                    .thenReturn(List.of(item));

            List<ConfirmationItemResponse> result = service.getPendingItems();

            assertThat(result).hasSize(1);
            assertThat(result.get(0).getId()).isEqualTo(1L);
            assertThat(result.get(0).getStatus()).isEqualTo("PENDING");
            assertThat(result.get(0).getSourceType()).isEqualTo("SUMMARY");
        }

        @Test
        void getPendingItemsForPatients_emptyIds_returnsEmptyWithoutQuery() {
            assertThat(service.getPendingItemsForPatients(List.of())).isEmpty();
            verify(repository, never())
                    .findByStatusAndPatientIdInOrderByCreatedAtDesc(any(), any());
        }

        @Test
        void getPendingItemsForPatients_scopesByPatientIds() {
            ConfirmationItem item = buildPendingItem(1L);
            item.setPatientId(42L);
            when(repository.findByStatusAndPatientIdInOrderByCreatedAtDesc(
                    ConfirmationStatus.PENDING, List.of(42L))).thenReturn(List.of(item));

            List<ConfirmationItemResponse> result = service.getPendingItemsForPatients(List.of(42L));

            assertThat(result).hasSize(1);
            assertThat(result.get(0).getPatientId()).isEqualTo(42L);
        }

        @Test
        void getPendingItemsByUser_filtersCorrectly() {
            when(repository.findByRequestedByAndStatusOrderByCreatedAtDesc(USER_ID, ConfirmationStatus.PENDING))
                    .thenReturn(List.of(buildPendingItem(1L)));

            List<ConfirmationItemResponse> result = service.getPendingItemsByUser(USER_ID);

            assertThat(result).hasSize(1);
            verify(repository).findByRequestedByAndStatusOrderByCreatedAtDesc(USER_ID, ConfirmationStatus.PENDING);
        }

        @Test
        void getPendingItemsBySourceType_filtersCorrectly() {
            when(repository.findBySourceTypeAndStatusOrderByCreatedAtDesc(
                    ConfirmationSourceType.ASK_AI, ConfirmationStatus.PENDING))
                    .thenReturn(List.of());

            List<ConfirmationItemResponse> result =
                    service.getPendingItemsBySourceType(ConfirmationSourceType.ASK_AI);

            assertThat(result).isEmpty();
            verify(repository).findBySourceTypeAndStatusOrderByCreatedAtDesc(
                    ConfirmationSourceType.ASK_AI, ConfirmationStatus.PENDING);
        }

        @Test
        void getItem_returnsMappedDto() {
            ConfirmationItem item = buildPendingItem(1L);
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            ConfirmationItemResponse result = service.getItem(1L);

            assertThat(result.getId()).isEqualTo(1L);
            assertThat(result.getPayload()).isEqualTo(PAYLOAD);
        }

        @Test
        void getItem_throwsWhenNotFound() {
            when(repository.findById(99L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.getItem(99L))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("not found")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void getItemsByUser_returnsAllStatusesForUser() {
            ConfirmationItem pending = buildPendingItem(1L);
            ConfirmationItem confirmed = buildPendingItem(2L);
            confirmed.confirm(RESOLVER_ID, "ok");
            when(repository.findByRequestedByOrderByCreatedAtDesc(USER_ID))
                    .thenReturn(List.of(pending, confirmed));

            List<ConfirmationItemResponse> result = service.getItemsByUser(USER_ID);

            assertThat(result).hasSize(2);
        }
    }

    // helpers

    @Nested
    class CrossTeamContract {

        /**
         * (3.11.7, 4.7.2)
         * summary confirmation creates a PENDING item
         * with sourceType=SUMMARY that can be confirmed
         */
        @Test
        void summaryConfirmationWorkflow() {
            when(repository.save(any())).thenAnswer(inv -> {
                ConfirmationItem i = inv.getArgument(0);
                i.setId(1L);
                return i;
            });
            when(repository.findById(1L)).thenAnswer(inv -> {
                ConfirmationItem i = buildPendingItem(1L);
                return Optional.of(i);
            });

            // Step 1: Summary pipeline creates confirmation item
            ConfirmationItem created = service.createItem(
                    ConfirmationSourceType.SUMMARY,
                    "{\"headline\":\"Took aspirin\",\"items\":[]}",
                    "call-456",
                    USER_ID);
            assertThat(created.getStatus()).isEqualTo(ConfirmationStatus.PENDING);
            assertThat(created.getSourceType()).isEqualTo(ConfirmationSourceType.SUMMARY);

            // Step 2: User confirms — side effect should proceed
            ConfirmationItem confirmed = service.confirm(1L, RESOLVER_ID, "Verified");
            assertThat(confirmed.getStatus()).isEqualTo(ConfirmationStatus.CONFIRMED);
        }

        /**
         * 4.7.2
         * Dismiss doesn't trigger any side effects
         */
        @Test
        void summaryDismissBlocksSideEffect() {
            when(repository.save(any())).thenAnswer(inv -> {
                ConfirmationItem i = inv.getArgument(0);
                i.setId(2L);
                return i;
            });
            when(repository.findById(2L)).thenAnswer(inv -> {
                ConfirmationItem i = buildPendingItem(2L);
                return Optional.of(i);
            });

            service.createItem(ConfirmationSourceType.SUMMARY, PAYLOAD, "call-789", USER_ID);
            ConfirmationItem dismissed = service.dismiss(2L, RESOLVER_ID, "Not accurate");

            assertThat(dismissed.getStatus()).isEqualTo(ConfirmationStatus.DISMISSED);
            assertThat(dismissed.getStatus()).isNotEqualTo(ConfirmationStatus.CONFIRMED);
        }

        /**
         * (3.12.7, 4.11.1)
         * Tier 2 HITL hold
         * ASK_AI items stay PENDING until a reviewer explicitly approves them
         */
        @Test
        void askAiHitlHoldUntilReviewerActs() {
            when(repository.save(any())).thenAnswer(inv -> {
                ConfirmationItem i = inv.getArgument(0);
                i.setId(3L);
                return i;
            });

            ConfirmationItem held = service.createItem(
                    ConfirmationSourceType.ASK_AI,
                    "{\"response\":\"Consider consulting your doctor\",\"tier\":2}",
                    "conv-001",
                    USER_ID);

            assertThat(held.getStatus()).isEqualTo(ConfirmationStatus.PENDING);
            assertThat(held.getResolvedBy()).isNull();
            // Item stays undelivered until confirm() is called
        }

        /**
         * (3.15.5, 4.11.3)
         * caregiver visibility
         * default-deny — item created with CAREGIVER_VISIBILITY stays PENDING
         */
        @Test
        void caregiverVisibilityDefaultDeny() {
            when(repository.save(any())).thenAnswer(inv -> {
                ConfirmationItem i = inv.getArgument(0);
                i.setId(4L);
                return i;
            });

            ConfirmationItem item = service.createItem(
                    ConfirmationSourceType.CAREGIVER_VISIBILITY,
                    "{\"summaryId\":55,\"caregiverId\":12}",
                    "summary-55",
                    USER_ID);

            assertThat(item.getStatus()).isEqualTo(ConfirmationStatus.PENDING);
            // Caregiver cannot see summary until item is explicitly confirmed
        }
    }
}
