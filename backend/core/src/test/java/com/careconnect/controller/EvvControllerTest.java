package com.careconnect.controller;

import com.careconnect.dto.evv.*;
import com.careconnect.model.User;
import com.careconnect.model.evv.EvvCorrection;
import com.careconnect.model.evv.EvvOfflineQueue;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.service.evv.EvvOfflineSyncService;
import com.careconnect.service.evv.EvvService;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.evv.EvvSubmissionService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvControllerTest {

    @Mock private EvvService evvService;
    @Mock private EvvSubmissionService submitter;
    @Mock private EvvOfflineSyncService offlineSyncService;
    @Mock private SecurityUtil securityUtil;
    @Mock private AuthorizationService authorizationService;
    @Mock private PatientRepository patientRepository;

    @InjectMocks
    private EvvController controller;

    // ── shared constants ──────────────────────────────────────────────────────

    private static final Long   DEFAULT_USER_ID = 1L;
    private static final Long   RECORD_ID       = 42L;
    private static final Long   CORRECTION_ID   = 10L;
    private static final String DEVICE_ID       = "device-abc-123";
    private static final String COMMENT         = "looks good";

    private User currentUser;

    @BeforeEach
    void setUpCurrentUser() throws Exception {
        currentUser = mock(User.class);
        lenient().when(currentUser.getId()).thenReturn(DEFAULT_USER_ID);
        when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
        lenient().doNothing().when(authorizationService).requireAdminOrCaregiver(any(User.class));
        lenient().when(currentUser.isPatient()).thenReturn(false);
    }

    // ── POST /v1/api/evv/records ──────────────────────────────────────────────

    @Nested
    class Create {

        @Test
        void returns200() throws Exception {
            final EvvRecordRequestDto req = new EvvRecordRequestDto();
            when(evvService.createRecord(req, DEFAULT_USER_ID)).thenReturn(new EvvRecord());

            final ResponseEntity<EvvRecord> response = controller.create(req);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final EvvRecordRequestDto req = new EvvRecordRequestDto();
            final EvvRecord record = EvvRecord.builder().id(RECORD_ID).build();
            when(evvService.createRecord(req, DEFAULT_USER_ID)).thenReturn(record);

            final ResponseEntity<EvvRecord> response = controller.create(req);

            assertThat(response.getBody()).isSameAs(record);
        }

        @Test
        void callsServiceWithDefaultUserId() throws Exception {
            final EvvRecordRequestDto req = new EvvRecordRequestDto();
            when(evvService.createRecord(req, DEFAULT_USER_ID)).thenReturn(new EvvRecord());

            controller.create(req);

            verify(evvService).createRecord(req, DEFAULT_USER_ID);
        }
    }

    // ── POST /v1/api/evv/records/{id}/review ─────────────────────────────────

    @Nested
    class Review {

        @Test
        void returns200_whenApproveIsTrue() throws Exception {
            final EvvReviewRequest action = new EvvReviewRequest(true, COMMENT);
            when(evvService.review(RECORD_ID, true, DEFAULT_USER_ID, COMMENT)).thenReturn(new EvvRecord());

            final ResponseEntity<EvvRecord> response = controller.review(RECORD_ID, action);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returns200_whenApproveIsFalse() throws Exception {
            final EvvReviewRequest action = new EvvReviewRequest(false, COMMENT);
            when(evvService.review(RECORD_ID, false, DEFAULT_USER_ID, COMMENT)).thenReturn(new EvvRecord());

            final ResponseEntity<EvvRecord> response = controller.review(RECORD_ID, action);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final EvvRecord record = EvvRecord.builder().id(RECORD_ID).build();
            final EvvReviewRequest action = new EvvReviewRequest(true, COMMENT);
            when(evvService.review(RECORD_ID, true, DEFAULT_USER_ID, COMMENT)).thenReturn(record);

            final ResponseEntity<EvvRecord> response = controller.review(RECORD_ID, action);

            assertThat(response.getBody()).isSameAs(record);
        }

        @Test
        void queuesForSubmission_whenApproveIsTrue() throws Exception {
            final EvvRecord record = new EvvRecord();
            final EvvReviewRequest action = new EvvReviewRequest(true, COMMENT);
            when(evvService.review(RECORD_ID, true, DEFAULT_USER_ID, COMMENT)).thenReturn(record);

            controller.review(RECORD_ID, action);

            verify(submitter).queueForSubmission(record, DEFAULT_USER_ID);
        }

        @Test
        void doesNotQueueForSubmission_whenApproveIsFalse() throws Exception {
            final EvvReviewRequest action = new EvvReviewRequest(false, COMMENT);
            when(evvService.review(RECORD_ID, false, DEFAULT_USER_ID, COMMENT)).thenReturn(new EvvRecord());

            controller.review(RECORD_ID, action);

            verifyNoInteractions(submitter);
        }

        @Test
        void callsServiceWithAllArguments() throws Exception {
            final EvvReviewRequest action = new EvvReviewRequest(false, COMMENT);
            when(evvService.review(RECORD_ID, false, DEFAULT_USER_ID, COMMENT)).thenReturn(new EvvRecord());

            controller.review(RECORD_ID, action);

            verify(evvService).review(RECORD_ID, false, DEFAULT_USER_ID, COMMENT);
        }
    }

    // ── POST /v1/api/evv/records/offline ─────────────────────────────────────

    @Nested
    class CreateOfflineRecord {

        @Test
        void returns200() throws Exception {
            final EvvRecordRequestDto req = new EvvRecordRequestDto();
            when(evvService.createOfflineRecord(req, DEFAULT_USER_ID, DEVICE_ID)).thenReturn(new EvvRecord());

            final ResponseEntity<EvvRecord> response = controller.createOfflineRecord(req, DEVICE_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final EvvRecordRequestDto req = new EvvRecordRequestDto();
            final EvvRecord record = EvvRecord.builder().id(5L).build();
            when(evvService.createOfflineRecord(req, DEFAULT_USER_ID, DEVICE_ID)).thenReturn(record);

            final ResponseEntity<EvvRecord> response = controller.createOfflineRecord(req, DEVICE_ID);

            assertThat(response.getBody()).isSameAs(record);
        }

        @Test
        void callsServiceWithDeviceIdAndDefaultUserId() throws Exception {
            final EvvRecordRequestDto req = new EvvRecordRequestDto();
            when(evvService.createOfflineRecord(req, DEFAULT_USER_ID, DEVICE_ID)).thenReturn(new EvvRecord());

            controller.createOfflineRecord(req, DEVICE_ID);

            verify(evvService).createOfflineRecord(req, DEFAULT_USER_ID, DEVICE_ID);
        }
    }

    // ── POST /v1/api/evv/records/correct ─────────────────────────────────────

    @Nested
    class CorrectRecord {

        @Test
        void returns200() throws Exception {
            final EvvCorrectionRequestDto req = new EvvCorrectionRequestDto();
            when(evvService.correctRecord(req, DEFAULT_USER_ID)).thenReturn(new EvvRecord());

            final ResponseEntity<EvvRecord> response = controller.correctRecord(req);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final EvvCorrectionRequestDto req = new EvvCorrectionRequestDto();
            final EvvRecord record = EvvRecord.builder().id(7L).build();
            when(evvService.correctRecord(req, DEFAULT_USER_ID)).thenReturn(record);

            final ResponseEntity<EvvRecord> response = controller.correctRecord(req);

            assertThat(response.getBody()).isSameAs(record);
        }

        @Test
        void callsServiceWithDefaultUserId() throws Exception {
            final EvvCorrectionRequestDto req = new EvvCorrectionRequestDto();
            when(evvService.correctRecord(req, DEFAULT_USER_ID)).thenReturn(new EvvRecord());

            controller.correctRecord(req);

            verify(evvService).correctRecord(req, DEFAULT_USER_ID);
        }
    }

    // ── POST /v1/api/evv/records/eor-approve ─────────────────────────────────

    @Nested
    class ApproveEor {

        @Test
        void returns200() throws Exception {
            final EorApprovalRequestDto req = new EorApprovalRequestDto();
            when(evvService.approveEor(req, DEFAULT_USER_ID)).thenReturn(new EvvRecord());

            final ResponseEntity<EvvRecord> response = controller.approveEor(req);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final EorApprovalRequestDto req = new EorApprovalRequestDto();
            final EvvRecord record = EvvRecord.builder().id(9L).build();
            when(evvService.approveEor(req, DEFAULT_USER_ID)).thenReturn(record);

            final ResponseEntity<EvvRecord> response = controller.approveEor(req);

            assertThat(response.getBody()).isSameAs(record);
        }

        @Test
        void callsServiceWithDefaultUserId() throws Exception {
            final EorApprovalRequestDto req = new EorApprovalRequestDto();
            when(evvService.approveEor(req, DEFAULT_USER_ID)).thenReturn(new EvvRecord());

            controller.approveEor(req);

            verify(evvService).approveEor(req, DEFAULT_USER_ID);
        }
    }

    // ── GET /v1/api/evv/records/search ───────────────────────────────────────

    @Nested
    class SearchRecords {

        @Test
        void returns200() throws Exception {
            final EvvSearchRequestDto searchRequest = new EvvSearchRequestDto();
            @SuppressWarnings("unchecked")
            final Page<EvvRecord> page = mock(Page.class);
            when(securityUtil.resolveCurrentUser()).thenReturn(mock(User.class));
            when(evvService.searchRecords(searchRequest)).thenReturn(page);

            final ResponseEntity<Page<EvvRecord>> response = controller.searchRecords(searchRequest);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsPageFromService() throws Exception {
            final EvvSearchRequestDto searchRequest = new EvvSearchRequestDto();
            @SuppressWarnings("unchecked")
            final Page<EvvRecord> page = mock(Page.class);
            when(securityUtil.resolveCurrentUser()).thenReturn(mock(User.class));
            when(evvService.searchRecords(searchRequest)).thenReturn(page);

            final ResponseEntity<Page<EvvRecord>> response = controller.searchRecords(searchRequest);

            assertThat(response.getBody()).isSameAs(page);
        }

        @Test
        void callsServiceWithSearchRequest() throws Exception {
            final EvvSearchRequestDto searchRequest = new EvvSearchRequestDto();
            @SuppressWarnings("unchecked")
            final Page<EvvRecord> page = mock(Page.class);
            when(securityUtil.resolveCurrentUser()).thenReturn(mock(User.class));
            when(evvService.searchRecords(searchRequest)).thenReturn(page);

            controller.searchRecords(searchRequest);

            verify(evvService).searchRecords(searchRequest);
        }
    }

    // ── GET /v1/api/evv/records/pending-eor-approvals ────────────────────────

    @Nested
    class GetPendingEorApprovals {

        @Test
        void returns200() throws Exception {
            when(evvService.getPendingEorApprovals()).thenReturn(List.of());

            final ResponseEntity<List<EvvRecord>> response = controller.getPendingEorApprovals();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsListFromService() throws Exception {
            final EvvRecord record = new EvvRecord();
            when(evvService.getPendingEorApprovals()).thenReturn(List.of(record));

            final ResponseEntity<List<EvvRecord>> response = controller.getPendingEorApprovals();

            assertThat(response.getBody()).containsExactly(record);
        }

        @Test
        void callsGetPendingEorApprovals() throws Exception {
            when(evvService.getPendingEorApprovals()).thenReturn(List.of());

            controller.getPendingEorApprovals();

            verify(evvService).getPendingEorApprovals();
        }
    }

    // ── GET /v1/api/evv/corrections/pending ──────────────────────────────────

    @Nested
    class GetPendingCorrections {

        @Test
        void returns200() throws Exception {
            when(evvService.getPendingCorrections()).thenReturn(List.of());

            final ResponseEntity<List<EvvCorrection>> response = controller.getPendingCorrections();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsListFromService() throws Exception {
            final EvvCorrection correction = new EvvCorrection();
            when(evvService.getPendingCorrections()).thenReturn(List.of(correction));

            final ResponseEntity<List<EvvCorrection>> response = controller.getPendingCorrections();

            assertThat(response.getBody()).containsExactly(correction);
        }

        @Test
        void callsGetPendingCorrections() throws Exception {
            when(evvService.getPendingCorrections()).thenReturn(List.of());

            controller.getPendingCorrections();

            verify(evvService).getPendingCorrections();
        }
    }

    // ── POST /v1/api/evv/corrections/{id}/approve ────────────────────────────

    @Nested
    class ApproveCorrection {

        @Test
        void returns200_withComment() throws Exception {
            when(evvService.approveCorrection(CORRECTION_ID, DEFAULT_USER_ID, COMMENT))
                    .thenReturn(new EvvCorrection());

            final ResponseEntity<EvvCorrection> response = controller.approveCorrection(CORRECTION_ID, COMMENT);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returns200_withNullComment() throws Exception {
            // comment is @RequestParam(required = false) — null is a valid value
            when(evvService.approveCorrection(CORRECTION_ID, DEFAULT_USER_ID, null))
                    .thenReturn(new EvvCorrection());

            final ResponseEntity<EvvCorrection> response = controller.approveCorrection(CORRECTION_ID, null);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final EvvCorrection correction = EvvCorrection.builder().id(CORRECTION_ID).build();
            when(evvService.approveCorrection(CORRECTION_ID, DEFAULT_USER_ID, COMMENT))
                    .thenReturn(correction);

            final ResponseEntity<EvvCorrection> response = controller.approveCorrection(CORRECTION_ID, COMMENT);

            assertThat(response.getBody()).isSameAs(correction);
        }

        @Test
        void callsServiceWithCorrectionIdDefaultUserIdAndComment() throws Exception {
            when(evvService.approveCorrection(CORRECTION_ID, DEFAULT_USER_ID, COMMENT))
                    .thenReturn(new EvvCorrection());

            controller.approveCorrection(CORRECTION_ID, COMMENT);

            verify(evvService).approveCorrection(CORRECTION_ID, DEFAULT_USER_ID, COMMENT);
        }

        @Test
        void callsServiceWithNullComment_whenCommentIsAbsent() throws Exception {
            when(evvService.approveCorrection(CORRECTION_ID, DEFAULT_USER_ID, null))
                    .thenReturn(new EvvCorrection());

            controller.approveCorrection(CORRECTION_ID, null);

            verify(evvService).approveCorrection(CORRECTION_ID, DEFAULT_USER_ID, null);
        }
    }

    // ── GET /v1/api/evv/offline/queue ────────────────────────────────────────

    @Nested
    class GetOfflineQueue {

        @Test
        void returns200() throws Exception {
            when(evvService.getOfflineQueue(DEFAULT_USER_ID)).thenReturn(List.of());

            final ResponseEntity<List<EvvOfflineQueue>> response = controller.getOfflineQueue();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsListFromService() throws Exception {
            final EvvOfflineQueue item = new EvvOfflineQueue();
            when(evvService.getOfflineQueue(DEFAULT_USER_ID)).thenReturn(List.of(item));

            final ResponseEntity<List<EvvOfflineQueue>> response = controller.getOfflineQueue();

            assertThat(response.getBody()).containsExactly(item);
        }

        @Test
        void callsServiceWithDefaultUserId() throws Exception {
            when(evvService.getOfflineQueue(DEFAULT_USER_ID)).thenReturn(List.of());

            controller.getOfflineQueue();

            verify(evvService).getOfflineQueue(DEFAULT_USER_ID);
        }
    }

    // ── POST /v1/api/evv/offline/sync ────────────────────────────────────────

    @Nested
    class SyncOfflineData {

        @Test
        void returns200() throws Exception {
            final ResponseEntity<String> response = controller.syncOfflineData();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void bodyIsFixedConfirmationMessage() throws Exception {
            final ResponseEntity<String> response = controller.syncOfflineData();

            assertThat(response.getBody()).isEqualTo("Offline data sync initiated");
        }

        @Test
        void callsOfflineSyncServiceWithDefaultUserId() throws Exception {
            controller.syncOfflineData();

            verify(offlineSyncService).syncCaregiverOfflineData(DEFAULT_USER_ID);
        }

        @Test
        void doesNotInteractWithEvvService() throws Exception {
            controller.syncOfflineData();

            verifyNoInteractions(evvService);
        }

        @Test
        void doesNotInteractWithSubmissionService() throws Exception {
            controller.syncOfflineData();

            verifyNoInteractions(submitter);
        }
    }

    // ── GET /v1/api/evv/offline/status ───────────────────────────────────────

    @Nested
    class GetOfflineStatus {

        @Test
        void returns200() throws Exception {
            when(offlineSyncService.getOfflineQueueStatus(DEFAULT_USER_ID)).thenReturn(List.of());

            final ResponseEntity<List<EvvOfflineQueue>> response = controller.getOfflineStatus();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsListFromService() throws Exception {
            final EvvOfflineQueue item = new EvvOfflineQueue();
            when(offlineSyncService.getOfflineQueueStatus(DEFAULT_USER_ID)).thenReturn(List.of(item));

            final ResponseEntity<List<EvvOfflineQueue>> response = controller.getOfflineStatus();

            assertThat(response.getBody()).containsExactly(item);
        }

        @Test
        void callsOfflineSyncServiceWithDefaultUserId() throws Exception {
            when(offlineSyncService.getOfflineQueueStatus(DEFAULT_USER_ID)).thenReturn(List.of());

            controller.getOfflineStatus();

            verify(offlineSyncService).getOfflineQueueStatus(DEFAULT_USER_ID);
        }

        @Test
        void doesNotInteractWithEvvService() throws Exception {
            when(offlineSyncService.getOfflineQueueStatus(DEFAULT_USER_ID)).thenReturn(List.of());

            controller.getOfflineStatus();

            verifyNoInteractions(evvService);
        }
    }
}
