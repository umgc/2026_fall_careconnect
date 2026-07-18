package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.lang.reflect.Method;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EvvOutboxProcessorTest {

    @Mock EvvOutboxService outboxService;
    @Mock EvvSubmissionService submissionService;
    @Mock EvvRecordRepository evvRecordRepository;

    @InjectMocks EvvOutboxProcessor processor;

    private Map<String, Object> outboxRow(long outboxId, long recordId) {
        Map<String, Object> row = new java.util.HashMap<>();
        row.put("id", outboxId);
        row.put("evv_record_id", recordId);
        return row;
    }

    // ─── processOutbox() ──────────────────────────────────────────────────────

    @Test
    void processOutbox_emptyPending_doesNothing() {
        // Arrange
        when(outboxService.fetchPending(50)).thenReturn(List.of());

        // Act
        processor.processOutbox();

        // Assert: empty-pending early return — no record lookups or submissions.
        verify(evvRecordRepository, never()).findByIdWithPatient(any());
        verify(submissionService, never()).submitRecord(any(), any());
        verify(outboxService, never()).markSent(any());
        verify(outboxService, never()).markFailed(any(), any());
    }

    @Test
    void processOutbox_successfulSubmission_marksSent() {
        // Arrange
        EvvRecord record = new EvvRecord();
        record.setId(100L);
        when(outboxService.fetchPending(50)).thenReturn(List.of(outboxRow(1L, 100L)));
        when(evvRecordRepository.findByIdWithPatient(100L)).thenReturn(Optional.of(record));

        // Act
        processor.processOutbox();

        // Assert
        verify(submissionService).submitRecord(record, 0L);
        verify(outboxService).markSent(1L);
        verify(outboxService, never()).markFailed(any(), any());
    }

    @Test
    void processOutbox_recordNotFound_marksFailedWithMessage() {
        // Arrange: orElseThrow's IllegalArgumentException is caught by the
        // surrounding try/catch and routed to markFailed.
        when(outboxService.fetchPending(50)).thenReturn(List.of(outboxRow(1L, 100L)));
        when(evvRecordRepository.findByIdWithPatient(100L)).thenReturn(Optional.empty());

        // Act
        processor.processOutbox();

        // Assert
        verify(outboxService).markFailed(eq(1L), eq("EVV record not found: 100"));
        verify(submissionService, never()).submitRecord(any(), any());
        verify(outboxService, never()).markSent(any());
    }

    @Test
    void processOutbox_submitRecordThrows_marksFailedWithExceptionMessage() {
        // Arrange
        EvvRecord record = new EvvRecord();
        record.setId(100L);
        when(outboxService.fetchPending(50)).thenReturn(List.of(outboxRow(1L, 100L)));
        when(evvRecordRepository.findByIdWithPatient(100L)).thenReturn(Optional.of(record));
        doThrow(new RuntimeException("downstream submission failed"))
                .when(submissionService).submitRecord(record, 0L);

        // Act
        processor.processOutbox();

        // Assert
        verify(outboxService).markFailed(eq(1L), eq("downstream submission failed"));
        verify(outboxService, never()).markSent(any());
    }

    @Test
    void processOutbox_multipleRows_processesEachIndependently() {
        // Arrange: first row succeeds, second row's record is missing.
        EvvRecord record = new EvvRecord();
        record.setId(100L);
        when(outboxService.fetchPending(50))
                .thenReturn(List.of(outboxRow(1L, 100L), outboxRow(2L, 200L)));
        when(evvRecordRepository.findByIdWithPatient(100L)).thenReturn(Optional.of(record));
        when(evvRecordRepository.findByIdWithPatient(200L)).thenReturn(Optional.empty());

        // Act
        processor.processOutbox();

        // Assert
        verify(outboxService).markSent(1L);
        verify(outboxService).markFailed(eq(2L), eq("EVV record not found: 200"));
    }

    // ─── truncate() (private helper) ──────────────────────────────────────────

    private String invokeTruncate(String msg) throws Exception {
        Method m = EvvOutboxProcessor.class.getDeclaredMethod("truncate", String.class);
        m.setAccessible(true);
        return (String) m.invoke(null, msg);
    }

    @Test
    void truncate_nullMessage_returnsNull() throws Exception {
        assertThat(invokeTruncate(null)).isNull();
    }

    @Test
    void truncate_shortMessage_returnsUnchanged() throws Exception {
        assertThat(invokeTruncate("short error")).isEqualTo("short error");
    }

    @Test
    void truncate_longMessage_truncatesTo500Characters() throws Exception {
        String longMessage = "x".repeat(600);

        String result = invokeTruncate(longMessage);

        assertThat(result).hasSize(500);
        assertThat(result).isEqualTo("x".repeat(500));
    }
}
