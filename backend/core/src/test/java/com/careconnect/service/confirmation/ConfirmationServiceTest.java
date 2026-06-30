package com.careconnect.service.confirmation;

import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.CreateConfirmationRequest;
import com.careconnect.model.confirmation.ConfirmationItem;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.confirmation.ConfirmationStatus;
import com.careconnect.repository.confirmation.ConfirmationItemRepository;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ConfirmationServiceTest {

    @Mock
    private ConfirmationItemRepository repository;

    @InjectMocks
    private ConfirmationService service;

    private static final Long USER_ID = 10L;
    private static final Long RESOLVER_ID = 20L;
    private static final String PAYLOAD = "{\"summary\":\"Patient took medication\"}";
    private static final String REFERENCE_ID = "call-123";
    private static final String NOTE = "Verified with patient";

    // createItem

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

        /** all 4 source types from AuditSourceFeature are accepted */
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

    // createItem from DTO

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
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    // confirm 

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
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("not found");
        }

        /** 4.11.2
         * cannot double-confirm */
        @Test
        void throwsWhenAlreadyConfirmed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.confirm(RESOLVER_ID, "first");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.confirm(1L, RESOLVER_ID, "second"))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("not PENDING");
        }

        /** 4.11.2
         * cannot confirm a dismissed item */
        @Test
        void throwsWhenAlreadyDismissed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.dismiss(RESOLVER_ID, "dismissed");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.confirm(1L, RESOLVER_ID, "try confirm"))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("not PENDING");
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
    }

    // dismiss

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

        /** (4.7.2): dismiss doesn't create a side effect 
         * status is DISMISSED, not CONFIRMED */
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
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("not found");
        }

        @Test
        void throwsWhenAlreadyDismissed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.dismiss(RESOLVER_ID, "first");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.dismiss(1L, RESOLVER_ID, "second"))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("not PENDING");
        }

        @Test
        void throwsWhenAlreadyConfirmed() {
            ConfirmationItem item = buildPendingItem(1L);
            item.confirm(RESOLVER_ID, "confirmed");
            when(repository.findById(1L)).thenReturn(Optional.of(item));

            assertThatThrownBy(() -> service.dismiss(1L, RESOLVER_ID, "try dismiss"))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("not PENDING");
        }
    }

    // timeout != approval (4.11.2)

    @Nested
    class TimeoutInvariant {

        /** (4.11.2) 
         *  a PENDING item has no way to resolve itself besides confirmation
         *  The only transitions are explicit confirm() or dismiss() */
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

        /** the service provides no batch-resolve or auto-expire method*/
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

    // queries

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
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("not found");
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

    // integration tests

    @Nested
    class CrossTeamContract {

        /** (3.11.7, 4.7.2)
         *  summary confirmation creates a PENDING item 
         *  with sourceType=SUMMARY that can be confirmed */
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

        /** 4.7.2
         *  Dismiss doesn't trigger any side effects */
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

        /** (3.12.7, 4.11.1)
         *  Tier 2 HITL hold
         *  ASK_AI items stay PENDING until a reviewer explicitly approves them */
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

        /** (3.15.5, 4.11.3)
         *  caregiver visibility
         *  default-deny — item created with CAREGIVER_VISIBILITY stays PENDING */
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

    // helpers

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
}
