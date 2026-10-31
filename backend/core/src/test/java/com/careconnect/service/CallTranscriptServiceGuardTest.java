package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.careconnect.repository.TranscriptArchiveLifecycleRepository;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Covers null-call guards, archive-only reads, merge of null rows and segment normalization edge
 * cases in {@link CallTranscriptService}. Repositories and collaborators are Mockito mocks.
 */
@DisplayName("CallTranscriptService guards and normalization")
class CallTranscriptServiceGuardTest {

    private static final String CALL_ID = "call-guard-1";

    private CallTranscriptSegmentRepository segments;
    private CallTranscriptArchiveService archive;
    private TranscriptArchiveLifecycleRepository lifecycle;
    private CallTranscriptService service;

    @BeforeEach
    void setUp() {
        segments = mock(CallTranscriptSegmentRepository.class);
        archive = mock(CallTranscriptArchiveService.class);
        lifecycle = mock(TranscriptArchiveLifecycleRepository.class);
        when(lifecycle.find(CALL_ID)).thenReturn(new TranscriptArchiveLifecycleRepository.ArchiveLifecycle(0L, false));
        service = new CallTranscriptService(segments, archive, mock(IndexingEventEmitter.class),
                mock(CallPatientResolver.class), lifecycle, mock(DatabaseLockService.class));
    }

    private static CallTranscriptSegment segment(final String text, final long startMs) {
        final CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setCallId(CALL_ID);
        segment.setSpeakerLabel("A");
        segment.setText(text);
        segment.setStartMs(startMs);
        return segment;
    }

    @Test
    @DisplayName("blank call ids short-circuit every read")
    void blankCallIds() {
        assertThat(service.getSegmentsForCall(" ")).isEmpty();
        assertThat(service.countSegments(null)).isZero();
        assertThat(service.hasTranscriptAccess(null, 1L)).isFalse();
        assertThat(service.captureSummarySnapshot(" ")).isNotNull();
        assertThat(service.captureIndexingSnapshot(null)).isNotNull();
        assertThat(service.archiveIfEligible(" ")).isFalse();
    }

    @Test
    @DisplayName("archive-only calls read and count from the archive; mixed calls merge without null rows")
    void archiveReadsAndMerge() {
        when(segments.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID)).thenReturn(List.of());
        when(archive.getArchivedSegments(CALL_ID)).thenReturn(List.of(segment("archived", 1)));
        when(archive.getArchivedSegmentCount(CALL_ID)).thenReturn(1L);
        when(segments.countByCallId(CALL_ID)).thenReturn(0L).thenReturn(2L);

        assertThat(service.getSegmentsForCall(CALL_ID)).hasSize(1);
        assertThat(service.countSegments(CALL_ID)).isEqualTo(1L);
        when(archive.isArchived(CALL_ID)).thenReturn(false);
        assertThat(service.countSegments(CALL_ID)).isEqualTo(2L);

        when(segments.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID))
                .thenReturn(Arrays.asList(null, segment("live", 2)));
        when(archive.getArchivedSegments(CALL_ID)).thenReturn(Arrays.asList(null, segment("archived", 1)));
        assertThat(service.captureSummarySnapshot(CALL_ID)).isNotNull();
        when(segments.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID)).thenReturn(List.of());
        when(archive.getArchivedSegments(CALL_ID)).thenReturn(List.of(segment(" ", 1), segment("archived", 2)));
        assertThat(service.captureSummarySnapshot(CALL_ID)).isNotNull();
    }

    @Test
    @DisplayName("participants who spoke have transcript access")
    void accessForSpeaker() {
        when(segments.existsByCallIdAndActorUserId(CALL_ID, 5L)).thenReturn(true);

        assertThat(service.hasTranscriptAccess(CALL_ID, 5L)).isTrue();
    }

    @Test
    @DisplayName("recorded segments normalize odd speaker labels and long sources")
    void recordSegments_normalizes() {
        when(segments.insertIdempotent(any(), any(), any(), any(), any(), any(), any(), any(), any())).thenReturn(1);
        final List<CallTranscriptService.TranscriptSegmentInput> inputs = new ArrayList<>();
        inputs.add(new CallTranscriptService.TranscriptSegmentInput(UUID.randomUUID(), "!!!", "one", 0L, 1L, "s".repeat(200)));
        inputs.add(new CallTranscriptService.TranscriptSegmentInput(UUID.randomUUID(), "X".repeat(300), "two", 1L, 2L, null));
        inputs.add(new CallTranscriptService.TranscriptSegmentInput(UUID.randomUUID(), null, "three", 2L, 3L, "src"));

        assertThat(service.recordSegments(CALL_ID, 1L, inputs)).isEqualTo(3);
    }
}
