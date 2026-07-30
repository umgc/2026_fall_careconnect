package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvSubmissionServiceTest {

    @Mock EvvIntegrationClient  client1;
    @Mock EvvOutboxService      outbox;
    @Mock EvvRecordRepository   evvRecordRepository;
    @Mock AuditLogger           audit;

    @InjectMocks EvvSubmissionService service;

    // The @InjectMocks injects `clients` as a List via field injection.
    // We need to set it explicitly since Spring normally auto-collects them.
    private EvvSubmissionService serviceWithClients() throws Exception {
        return new EvvSubmissionService(List.of(client1), outbox, evvRecordRepository, audit);
    }

    // ─── destinationFor() ────────────────────────────────────────────────────

    @Test
    void destinationFor_maryland_returnsMarylandInfoOnly() throws Exception {
        assertThat(serviceWithClients().destinationFor("MD")).isEqualTo("maryland-info-only");
    }

    @Test
    void destinationFor_dc_returnsDcSandata() throws Exception {
        assertThat(serviceWithClients().destinationFor("DC")).isEqualTo("dc-sandata");
    }

    @Test
    void destinationFor_virginia_returnsVirginiaMco() throws Exception {
        assertThat(serviceWithClients().destinationFor("VA")).isEqualTo("virginia-mco");
    }

    @Test
    void destinationFor_lowercase_mapsCorrectly() throws Exception {
        assertThat(serviceWithClients().destinationFor("md")).isEqualTo("maryland-info-only");
    }

    @Test
    void destinationFor_unsupportedState_throwsIllegalArgument() throws Exception {
        assertThatThrownBy(() -> serviceWithClients().destinationFor("TX"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Unsupported state code: TX");
    }

    // ─── queueForSubmission() ─────────────────────────────────────────────────

    @Test
    void queueForSubmission_callsOutboxEnqueueAndAuditLog() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("MD");

        final EvvSubmissionService svc = serviceWithClients();
        svc.queueForSubmission(record, 7L);

        verify(outbox).enqueue(record, "maryland-info-only");
        verify(audit).log(eq(record), eq(7L), eq("SUBMISSION_QUEUED"), any(Map.class));
    }

    // ─── submitRecord() ───────────────────────────────────────────────────────

    @Test
    void submitRecord_success_callsClientAndLogsSubmitted() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("DC");

        final EvvSubmissionService svc = serviceWithClients();
        svc.submitRecord(record, 5L);

        verify(client1).submit(record);
        verify(audit).log(eq(record), eq(5L), eq("SUBMITTED"), any(Map.class));
    }

    @Test
    void submitRecord_success_auditDetailsContainDestinationAndSuccessFlag() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("DC");

        final EvvSubmissionService svc = serviceWithClients();
        svc.submitRecord(record, 5L);

        @SuppressWarnings("unchecked")
        final ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(audit).log(eq(record), eq(5L), eq("SUBMITTED"), captor.capture());
        assertThat(captor.getValue()).containsEntry("destination", "dc-sandata");
        assertThat(captor.getValue()).containsEntry("success", true);
    }

    @Test
    void submitRecord_success_doesNotThrow() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("VA");

        final EvvSubmissionService svc = serviceWithClients();
        svc.submitRecord(record, 5L); // should complete without exception
    }

    @Test
    void submitRecord_noMatchingClient_throwsRuntimeException() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("VA");

        final EvvSubmissionService svc = new EvvSubmissionService(List.of(), outbox, evvRecordRepository, audit);

        assertThatThrownBy(() -> svc.submitRecord(record, 5L))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Failed to submit EVV record");
    }

    @Test
    void submitRecord_noMatchingClient_logsSubmissionFailed() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("MD");

        final EvvSubmissionService svc = new EvvSubmissionService(List.of(), outbox, evvRecordRepository, audit);

        assertThatThrownBy(() -> svc.submitRecord(record, 5L)).isInstanceOf(RuntimeException.class);

        // The service logs SUBMISSION_FAILED both in the inner block and the outer catch
        verify(audit, atLeast(1)).log(eq(record), eq(5L), eq("SUBMISSION_FAILED"), any(Map.class));
    }

    @Test
    void submitRecord_clientThrowsException_throwsRuntimeExceptionAndLogsFailure() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("VA");
        doThrow(new RuntimeException("Downstream API error")).when(client1).submit(record);

        final EvvSubmissionService svc = serviceWithClients();

        assertThatThrownBy(() -> svc.submitRecord(record, 5L))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Failed to submit EVV record");

        verify(audit, atLeast(1)).log(eq(record), eq(5L), eq("SUBMISSION_FAILED"), any(Map.class));
    }

    @Test
    void submitRecord_unsupportedState_throwsIllegalArgumentBeforeCallingClient() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        when(record.getStateCode()).thenReturn("TX");

        final EvvSubmissionService svc = serviceWithClients();

        assertThatThrownBy(() -> svc.submitRecord(record, 5L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Unsupported state code: TX");

        verify(client1, never()).submit(any());
        verify(audit, never()).log(eq(record), any(), eq("SUBMITTED"), any());
    }

    // ─── buildLocationDetails (private helper) ────────────────────────────────
    // Existing tests above only ever exercise this with every location field
    // null; drive every lat-only/lng-only combination directly via reflection.

    private Map<String, Object> invokeBuildLocationDetails(EvvRecord record) throws Exception {
        java.lang.reflect.Method m =
                EvvSubmissionService.class.getDeclaredMethod("buildLocationDetails", EvvRecord.class);
        m.setAccessible(true);
        return (Map<String, Object>) m.invoke(service, record);
    }

    @Test
    void buildLocationDetails_legacyLatOnly_includesLegacyFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).locationLat(38.9).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("locationLat");
    }

    @Test
    void buildLocationDetails_legacyLngOnly_includesLegacyFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).locationLng(-77.0).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("locationLng");
    }

    @Test
    void buildLocationDetails_checkinLatOnly_includesCheckinFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkinLocationLat(38.9).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkinLocationLat");
    }

    @Test
    void buildLocationDetails_checkinLngOnly_includesCheckinFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkinLocationLng(-77.0).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkinLocationLng");
    }

    @Test
    void buildLocationDetails_checkoutLatOnly_includesCheckoutFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkoutLocationLat(38.9).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkoutLocationLat");
    }

    @Test
    void buildLocationDetails_checkoutLngOnly_includesCheckoutFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkoutLocationLng(-77.0).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkoutLocationLng");
    }
}
