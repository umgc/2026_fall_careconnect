package com.careconnect.service.visibility;

import com.careconnect.dto.visibility.VisibilityDtos.VisibilityResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.model.visibility.CaregiverSummaryVisibility;
import com.careconnect.model.visibility.VisibilityStatus;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.visibility.CaregiverSummaryVisibilityRepository;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.service.safety.AiAuditLedgerService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CaregiverVisibilityServiceTest {

    private static final Long CG = 5L, PT = 9L, REVIEWER = 1L;
    @Mock
    CaregiverSummaryVisibilityRepository repository;
    @Mock
    ConfirmationService confirmationService;
    @Mock
    AiAuditLedgerService auditLedgerService;
    @Mock
    UserRepository userRepository;
    @Mock
    CaregiverPatientLinkRepository caregiverPatientLinkRepository;
    @InjectMocks
    CaregiverVisibilityService service;

    private CaregiverSummaryVisibility record(VisibilityStatus status) {
        return CaregiverSummaryVisibility.builder()
                .id(100L).caregiverUserId(CG).patientUserId(PT).status(status).build();
    }

    /**
     * Stubs an active caregiver-patient link so submitForReview passes the relationship gate.
     */
    private void stubActiveLink() {
        User cg = new User();
        cg.setId(CG);
        User pt = new User();
        pt.setId(PT);
        lenient().when(userRepository.findById(CG)).thenReturn(Optional.of(cg));
        lenient().when(userRepository.findById(PT)).thenReturn(Optional.of(pt));
        lenient().when(caregiverPatientLinkRepository.existsActiveNonExpiredLink(eq(cg), eq(pt), any()))
                .thenReturn(true);
    }

    // Default-deny

    @Test
    void canViewSummaries_defaultDeny_whenNoGrantExists() {
        when(repository.existsByCaregiverUserIdAndPatientUserIdAndStatus(CG, PT, VisibilityStatus.GRANTED))
                .thenReturn(false);
        assertThat(service.canViewSummaries(CG, PT)).isFalse();
    }

    @Test
    void canViewSummaries_true_onlyWhenGranted() {
        when(repository.existsByCaregiverUserIdAndPatientUserIdAndStatus(CG, PT, VisibilityStatus.GRANTED))
                .thenReturn(true);
        assertThat(service.canViewSummaries(CG, PT)).isTrue();
    }

    @Test
    void getStatus_noRecord_reportsNoneAndCannotView() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT)).thenReturn(Optional.empty());
        VisibilityResponse r = service.getStatus(CG, PT);
        assertThat(r.getStatus()).isEqualTo("NONE");
        assertThat(r.isCanViewSummaries()).isFalse();
    }

    // Review gate

    @Test
    void submitForReview_setsPending_andQueuesConfirmationItem() {
        stubActiveLink();
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT)).thenReturn(Optional.empty());
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        VisibilityResponse r = service.submitForReview(CG, PT, REVIEWER);

        assertThat(r.getStatus()).isEqualTo("PENDING_REVIEW");
        assertThat(r.isCanViewSummaries()).isFalse();
        verify(confirmationService).createItem(
                eq(ConfirmationSourceType.CAREGIVER_VISIBILITY), anyString(), anyString(), eq(REVIEWER), eq(PT));
    }

    @Test
    void submitForReview_withoutActiveLink_throws() {
        when(userRepository.findById(CG)).thenReturn(Optional.of(new User()));
        when(userRepository.findById(PT)).thenReturn(Optional.of(new User()));
        when(caregiverPatientLinkRepository.existsActiveNonExpiredLink(any(), any(), any()))
                .thenReturn(false);

        assertThatThrownBy(() -> service.submitForReview(CG, PT, REVIEWER))
                .isInstanceOf(AppException.class);
        verify(repository, never()).save(any());
        verify(confirmationService, never()).createItem(any(), anyString(), anyString(), anyLong());
    }

    // Grant and revoke

    @Test
    void grant_setsGranted_andRecordsReviewer_andAudits() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT))
                .thenReturn(Optional.of(record(VisibilityStatus.PENDING_REVIEW)));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        VisibilityResponse r = service.grant(CG, PT, REVIEWER);

        assertThat(r.getStatus()).isEqualTo("GRANTED");
        assertThat(r.isCanViewSummaries()).isTrue();
        assertThat(r.getReviewedBy()).isEqualTo(REVIEWER);
        verify(auditLedgerService).log(any(), eq(AuditSourceFeature.CAREGIVER_VISIBILITY),
                eq(REVIEWER), eq(PT), any(), any());
    }

    @Test
    void revoke_setsRevoked_andCannotView() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT))
                .thenReturn(Optional.of(record(VisibilityStatus.GRANTED)));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        VisibilityResponse r = service.revoke(CG, PT, REVIEWER);

        assertThat(r.getStatus()).isEqualTo("REVOKED");
        assertThat(r.isCanViewSummaries()).isFalse();
    }

    @Test
    void approveFromReview_whenPending_grants() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT))
                .thenReturn(Optional.of(record(VisibilityStatus.PENDING_REVIEW)));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.approveFromReview(CG, PT, REVIEWER);

        ArgumentCaptor<CaregiverSummaryVisibility> captor =
                ArgumentCaptor.forClass(CaregiverSummaryVisibility.class);
        verify(repository).save(captor.capture());
        assertThat(captor.getValue().getStatus()).isEqualTo(VisibilityStatus.GRANTED);
    }

    @Test
    void approveFromReview_whenNotPending_isNoOp_doesNotThrow() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT))
                .thenReturn(Optional.of(record(VisibilityStatus.REVOKED)));

        service.approveFromReview(CG, PT, REVIEWER); // must not throw

        verify(repository, never()).save(any());
    }

    @Test
    void grant_withoutPriorReview_throws() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.grant(CG, PT, REVIEWER))
                .isInstanceOf(AppException.class);
        verify(repository, never()).save(any());
    }

    @Test
    void grant_notPendingReview_throws() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT))
                .thenReturn(Optional.of(record(VisibilityStatus.REVOKED)));

        assertThatThrownBy(() -> service.grant(CG, PT, REVIEWER))
                .isInstanceOf(AppException.class);
        verify(repository, never()).save(any());
    }

    @Test
    void auditFailure_doesNotBreakGrant() {
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT))
                .thenReturn(Optional.of(record(VisibilityStatus.PENDING_REVIEW)));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(auditLedgerService.log(any(), any(), anyLong(), anyLong(), any(), any()))
                .thenThrow(new RuntimeException("ledger down"));

        VisibilityResponse r = service.grant(CG, PT, REVIEWER);
        assertThat(r.getStatus()).isEqualTo("GRANTED");
    }

    @Test
    void submitForReview_doesNotGrantAccess() {
        stubActiveLink();
        when(repository.findByCaregiverUserIdAndPatientUserId(CG, PT)).thenReturn(Optional.empty());
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.submitForReview(CG, PT, REVIEWER);

        verify(repository, never()).existsByCaregiverUserIdAndPatientUserIdAndStatus(
                anyLong(), anyLong(), eq(VisibilityStatus.GRANTED));
    }
}
