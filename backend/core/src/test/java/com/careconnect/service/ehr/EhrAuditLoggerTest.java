package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class EhrAuditLoggerTest {

    @Mock
    EhrAuditEventRepository repo;

    @InjectMocks
    EhrAuditLogger auditLogger;

    private EhrAuditEvent captureSaved() {
        final ArgumentCaptor<EhrAuditEvent> captor = ArgumentCaptor.forClass(EhrAuditEvent.class);
        verify(repo).save(captor.capture());
        return captor.getValue();
    }

    @Test
    void log_savesSuccessfulAttemptWithAllFields() {
        final Map<String, Object> details = Map.of("latencyMs", 412);

        auditLogger.log(7L, "MEDICARE", "Coverage", EhrRetrievalOutcome.SUCCESS, 42L, 3, details);

        final EhrAuditEvent saved = captureSaved();
        assertThat(saved.getPatientId()).isEqualTo(7L);
        assertThat(saved.getSource()).isEqualTo("MEDICARE");
        assertThat(saved.getResourceType()).isEqualTo("Coverage");
        assertThat(saved.getOutcome()).isEqualTo(EhrRetrievalOutcome.SUCCESS);
        assertThat(saved.getActorUserId()).isEqualTo(42L);
        assertThat(saved.getRecordCount()).isEqualTo(3);
        assertThat(saved.getDetails()).isEqualTo(details);
    }

    @Test
    void log_systemInitiatedEmptyAttempt_hasNoActorAndZeroRecords() {
        auditLogger.log(7L, "MEDICARE", "ExplanationOfBenefit",
                EhrRetrievalOutcome.EMPTY, null, 0, null);

        final EhrAuditEvent saved = captureSaved();
        assertThat(saved.getOutcome()).isEqualTo(EhrRetrievalOutcome.EMPTY);
        assertThat(saved.getActorUserId()).isNull();
        assertThat(saved.getRecordCount()).isZero();
        assertThat(saved.getDetails()).isNull();
    }

    @Test
    void log_failedAttempt_recordsNoCountAndKeepsErrorDetails() {
        final Map<String, Object> details = Map.of("errorCode", "ERR-MCR-05");

        auditLogger.log(7L, "MEDICARE", "Patient",
                EhrRetrievalOutcome.FAILURE, 42L, null, details);

        final EhrAuditEvent saved = captureSaved();
        assertThat(saved.getOutcome()).isEqualTo(EhrRetrievalOutcome.FAILURE);
        assertThat(saved.getRecordCount()).isNull();
        assertThat(saved.getDetails()).isEqualTo(details);
    }
}
