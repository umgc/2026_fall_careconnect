package com.careconnect.controller;

import com.careconnect.dto.evv.EvvSearchRequestDto;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.evv.EvvRecordRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.evv.EvvOfflineSyncService;
import com.careconnect.service.evv.EvvService;
import com.careconnect.service.evv.EvvSubmissionService;
import com.careconnect.service.evv.HhaExchangeBatchSubmissionService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class EvvControllerHhaExchangeCoverageTest {

    @Mock private EvvService evvService;
    @Mock private EvvSubmissionService submitter;
    @Mock private HhaExchangeBatchSubmissionService hhaExchangeSubmitter;
    @Mock private EvvOfflineSyncService offlineSyncService;
    @Mock private EvvRecordRepository evvRecordRepository;
    @Mock private SecurityUtil securityUtil;
    @Mock private AuthorizationService authorizationService;
    @Mock private PatientRepository patientRepository;

    private EvvController controller;
    private final User admin = User.builder().id(1L).role(Role.ADMIN).build();

    @BeforeEach
    void setUp() {
        controller = new EvvController(evvService, submitter, hhaExchangeSubmitter, offlineSyncService,
                evvRecordRepository, securityUtil, authorizationService, patientRepository);
        when(securityUtil.resolveCurrentUser()).thenReturn(admin);
    }

    @Test
    void hhaExchangeEndpointsMapOutcomes() throws Exception {
        List<Long> ids = List.of(1L, 2L);
        assertThat(controller.getHhaExchangeEligibleRecords().getStatusCode().value()).isEqualTo(200);

        when(hhaExchangeSubmitter.buildPayload(anyList())).thenReturn("payload")
                .thenThrow(new IllegalArgumentException("bad ids"))
                .thenThrow(new IllegalStateException("boom"));
        assertThat(controller.getHhaExchangePayload(ids).getStatusCode().value()).isEqualTo(200);
        assertThat(controller.getHhaExchangePayload(ids).getStatusCode().value()).isEqualTo(400);
        assertThat(controller.getHhaExchangePayload(ids).getStatusCode().value()).isEqualTo(500);

        when(hhaExchangeSubmitter.getPayloadJson(anyList())).thenReturn("{}")
                .thenThrow(new IllegalArgumentException("bad ids"));
        assertThat(controller.getHhaExchangePayloadJson(ids).getStatusCode().value()).isEqualTo(200);
        assertThat(controller.getHhaExchangePayloadJson(ids).getStatusCode().value()).isEqualTo(400);

        doNothing().doThrow(new IllegalArgumentException("bad")).doThrow(new RuntimeException("down"))
                .when(hhaExchangeSubmitter).submitBatch(anyList(), any());
        assertThat(controller.submitToHhaExchange(ids).getStatusCode().value()).isEqualTo(200);
        assertThat(controller.submitToHhaExchange(ids).getStatusCode().value()).isEqualTo(400);
        assertThat(controller.submitToHhaExchange(ids).getStatusCode().value()).isEqualTo(500);
    }

    @Test
    void patientSearchIsScopedToOwnRecord() throws Exception {
        User patientUser = User.builder().id(2L).role(Role.PATIENT).build();
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        Patient patient = new Patient();
        patient.setId(9L);
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        EvvSearchRequestDto search = new EvvSearchRequestDto();
        assertThat(controller.searchRecords(search).getStatusCode().value()).isEqualTo(200);
        assertThat(search.getPatientId()).isEqualTo(9L);
    }
}
