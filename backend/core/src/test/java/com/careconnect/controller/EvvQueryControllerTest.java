package com.careconnect.controller;

import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvQueryControllerTest {

    private static final String STATUS = "PENDING";
    private static final Long CAREGIVER_ID = 7L;
    @Mock
    private EvvRecordRepository evvRecordRepository;
    @Mock
    private SecurityUtil securityUtil;

    // ── shared constants ──────────────────────────────────────────────────────
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private EvvQueryController controller;

    // ── GET /v1/api/evv/records ───────────────────────────────────────────────
    //
    // Branch table:
    //   status != null && caregiverId != null  →  findByCaregiverIdAndStatus
    //   status != null && caregiverId == null  →  findByStatus
    //   status == null  (any caregiverId)      →  findAll

    @Nested
    class List_BothNull {

        @Test
        void callsFindAll_whenBothParamsAreNull() throws Exception {
            when(evvRecordRepository.findAll()).thenReturn(List.of());

            controller.list(null, null);

            verify(evvRecordRepository).findAll();
        }

        @Test
        void returnsResultFromFindAll() throws Exception {
            final EvvRecord record = new EvvRecord();
            when(evvRecordRepository.findAll()).thenReturn(List.of(record));

            final List<EvvRecord> result = controller.list(null, null);

            assertThat(result).containsExactly(record);
        }

        @Test
        void doesNotCallFindByStatus_whenBothNull() throws Exception {
            when(evvRecordRepository.findAll()).thenReturn(List.of());

            controller.list(null, null);

            verify(evvRecordRepository, never()).findByStatus(any());
        }

        @Test
        void doesNotCallFindByCaregiverIdAndStatus_whenBothNull() throws Exception {
            when(evvRecordRepository.findAll()).thenReturn(List.of());

            controller.list(null, null);

            verify(evvRecordRepository, never()).findByCaregiverIdAndStatus(any(), any());
        }
    }

    @Nested
    class List_StatusOnly {

        @Test
        void callsFindByStatus_whenStatusProvidedAndCaregiverIdIsNull() throws Exception {
            when(evvRecordRepository.findByStatus(STATUS)).thenReturn(List.of());

            controller.list(STATUS, null);

            verify(evvRecordRepository).findByStatus(STATUS);
        }

        @Test
        void returnsResultFromFindByStatus() throws Exception {
            final EvvRecord record = new EvvRecord();
            when(evvRecordRepository.findByStatus(STATUS)).thenReturn(List.of(record));

            final List<EvvRecord> result = controller.list(STATUS, null);

            assertThat(result).containsExactly(record);
        }

        @Test
        void doesNotCallFindAll_whenStatusProvided() throws Exception {
            when(evvRecordRepository.findByStatus(STATUS)).thenReturn(List.of());

            controller.list(STATUS, null);

            verify(evvRecordRepository, never()).findAll();
        }

        @Test
        void doesNotCallFindByCaregiverIdAndStatus_whenOnlyStatusProvided() throws Exception {
            when(evvRecordRepository.findByStatus(STATUS)).thenReturn(List.of());

            controller.list(STATUS, null);

            verify(evvRecordRepository, never()).findByCaregiverIdAndStatus(any(), any());
        }

        @Test
        void passesStatusValueCorrectlyToRepository() throws Exception {
            final String specificStatus = "APPROVED";
            when(evvRecordRepository.findByStatus(specificStatus)).thenReturn(List.of());

            controller.list(specificStatus, null);

            verify(evvRecordRepository).findByStatus(specificStatus);
        }
    }

    @Nested
    class List_BothStatusAndCaregiverId {

        @Test
        void callsFindByCaregiverIdAndStatus_whenBothProvided() throws Exception {
            when(evvRecordRepository.findByCaregiverIdAndStatus(CAREGIVER_ID, STATUS)).thenReturn(List.of());

            controller.list(STATUS, CAREGIVER_ID);

            verify(evvRecordRepository).findByCaregiverIdAndStatus(CAREGIVER_ID, STATUS);
        }

        @Test
        void returnsResultFromFindByCaregiverIdAndStatus() throws Exception {
            final EvvRecord record = new EvvRecord();
            when(evvRecordRepository.findByCaregiverIdAndStatus(CAREGIVER_ID, STATUS))
                    .thenReturn(List.of(record));

            final List<EvvRecord> result = controller.list(STATUS, CAREGIVER_ID);

            assertThat(result).containsExactly(record);
        }

        @Test
        void doesNotCallFindAll_whenBothProvided() throws Exception {
            when(evvRecordRepository.findByCaregiverIdAndStatus(CAREGIVER_ID, STATUS)).thenReturn(List.of());

            controller.list(STATUS, CAREGIVER_ID);

            verify(evvRecordRepository, never()).findAll();
        }

        @Test
        void doesNotCallFindByStatus_whenBothProvided() throws Exception {
            when(evvRecordRepository.findByCaregiverIdAndStatus(CAREGIVER_ID, STATUS)).thenReturn(List.of());

            controller.list(STATUS, CAREGIVER_ID);

            verify(evvRecordRepository, never()).findByStatus(any());
        }

        @Test
        void passesBothArgumentsCorrectlyToRepository() throws Exception {
            final Long specificCaregiverId = 99L;
            final String specificStatus = "SUBMITTED";
            when(evvRecordRepository.findByCaregiverIdAndStatus(specificCaregiverId, specificStatus))
                    .thenReturn(List.of());

            controller.list(specificStatus, specificCaregiverId);

            verify(evvRecordRepository).findByCaregiverIdAndStatus(specificCaregiverId, specificStatus);
        }
    }

    @Nested
    class List_CaregiverIdOnlyWithoutStatus {

        // When caregiverId != null but status == null:
        // the first if fails (status is null), the second if also fails,
        // so findAll() is invoked — caregiverId without status is treated as
        // "no filter" and the full record list is returned.

        @Test
        void callsFindAll_whenOnlyCaregiverIdProvided() throws Exception {
            when(evvRecordRepository.findAll()).thenReturn(List.of());

            controller.list(null, CAREGIVER_ID);

            verify(evvRecordRepository).findAll();
        }

        @Test
        void returnsResultFromFindAll_whenOnlyCaregiverIdProvided() throws Exception {
            final EvvRecord record = new EvvRecord();
            when(evvRecordRepository.findAll()).thenReturn(List.of(record));

            final List<EvvRecord> result = controller.list(null, CAREGIVER_ID);

            assertThat(result).containsExactly(record);
        }

        @Test
        void doesNotCallFindByStatus_whenOnlyCaregiverIdProvided() throws Exception {
            when(evvRecordRepository.findAll()).thenReturn(List.of());

            controller.list(null, CAREGIVER_ID);

            verify(evvRecordRepository, never()).findByStatus(any());
        }

        @Test
        void doesNotCallFindByCaregiverIdAndStatus_whenStatusIsNull() throws Exception {
            when(evvRecordRepository.findAll()).thenReturn(List.of());

            controller.list(null, CAREGIVER_ID);

            verify(evvRecordRepository, never()).findByCaregiverIdAndStatus(any(), any());
        }
    }
}
