package com.careconnect.service;

import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("CallTranscriptService Tests")
class CallTranscriptServiceTest {

    @Mock
    private CallTranscriptSegmentRepository callTranscriptSegmentRepository;

    @Mock
    private com.careconnect.indexing.IndexingEventEmitter indexingEventEmitter;

    @Mock
    private CallTranscriptArchiveService callTranscriptArchiveService;

    @Mock
    private CallPatientResolver callPatientResolver;

    private CallTranscriptService service;

    private static final String CALL_ID = "call-1";

    @BeforeEach
    void setUp() {
        service = new CallTranscriptService(
                callTranscriptSegmentRepository,
                callTranscriptArchiveService,
                indexingEventEmitter,
                callPatientResolver);
        org.mockito.Mockito.lenient()
                .when(callPatientResolver.requirePatientId(CALL_ID))
                .thenReturn(42L);
    }

    private CallTranscriptSegment segment(
            String speaker,
            String text,
            Long startMs,
            Long endMs,
            String source,
            Long actorUserId,
            LocalDateTime occurredAt
    ) {
        CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setCallId(CALL_ID);
        segment.setSpeakerLabel(speaker);
        segment.setText(text);
        segment.setStartMs(startMs);
        segment.setEndMs(endMs);
        segment.setSource(source);
        segment.setActorUserId(actorUserId);
        segment.setOccurredAt(occurredAt);
        return segment;
    }

    @Nested
    @DisplayName("recordSegments")
    class RecordSegmentsTests {

        @Test
        @DisplayName("returns zero when callId is blank or segments are empty")
        void recordSegments_blankOrEmpty_returnsZero() {
            assertThat(service.recordSegments(" ", 1L, List.of())).isZero();
            verify(callTranscriptSegmentRepository, never()).save(any(CallTranscriptSegment.class));
        }

        @Test
        @DisplayName("throws when more than 200 segments are submitted")
        void recordSegments_tooManySegments_throws() {
            List<CallTranscriptService.TranscriptSegmentInput> inputs =
                    java.util.stream.IntStream.range(0, 201)
                            .mapToObj(i -> new CallTranscriptService.TranscriptSegmentInput("speaker", "text", (long) i, (long) i, "SRC"))
                            .toList();

            assertThatThrownBy(() -> service.recordSegments(CALL_ID, 1L, inputs))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Too many transcript segments");
        }

        @Test
        @DisplayName("saves normalized segments, truncates text, and skips null inputs")
        void recordSegments_normalizesAndSaves() {
            String longText = "x".repeat(1300);
            List<CallTranscriptService.TranscriptSegmentInput> inputs = new java.util.ArrayList<>(List.of(
                    new CallTranscriptService.TranscriptSegmentInput(" nurse#1 ", " hello there ", 10L, 20L, " local!source "),
                    new CallTranscriptService.TranscriptSegmentInput("$$$", "   ", 30L, 40L, null),
                    new CallTranscriptService.TranscriptSegmentInput(" patient ", longText, 50L, 60L, null)
            ));
            inputs.add(1, null);
            when(callTranscriptSegmentRepository
                    .findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID))
                    .thenReturn(List.of(
                            segment("NURSE1", "hello there", 10L, 20L,
                                    "localsource", 7L, LocalDateTime.now()),
                            segment("PATIENT", "x".repeat(1200), 50L, 60L,
                                    "CLIENT_TRANSCRIPT", 7L, LocalDateTime.now())));
            when(callTranscriptArchiveService.getArchivedSegments(CALL_ID))
                    .thenReturn(List.of());

            int saved = service.recordSegments("  " + CALL_ID + "  ", 7L, inputs);

            assertThat(saved).isEqualTo(2);

            ArgumentCaptor<CallTranscriptSegment> captor = ArgumentCaptor.forClass(CallTranscriptSegment.class);
            verify(callTranscriptSegmentRepository, org.mockito.Mockito.times(2)).save(captor.capture());
            List<CallTranscriptSegment> stored = captor.getAllValues();

            assertThat(stored.get(0).getCallId()).isEqualTo(CALL_ID);
            assertThat(stored.get(0).getActorUserId()).isEqualTo(7L);
            assertThat(stored.get(0).getSpeakerLabel()).isEqualTo("NURSE1");
            assertThat(stored.get(0).getText()).isEqualTo("hello there");
            assertThat(stored.get(0).getSource()).isEqualTo("localsource");

            assertThat(stored.get(1).getSpeakerLabel()).isEqualTo("PATIENT");
            assertThat(stored.get(1).getText()).hasSize(1200);
            assertThat(stored.get(1).getSource()).isEqualTo("CLIENT_TRANSCRIPT");
            assertThat(stored.get(1).getOccurredAt()).isNotNull();
            final ArgumentCaptor<TranscriptIndexedPayload> eventCaptor =
                    ArgumentCaptor.forClass(TranscriptIndexedPayload.class);
            verify(indexingEventEmitter).emitTranscriptIndexed(eventCaptor.capture());
            assertThat(eventCaptor.getValue().patientId()).isEqualTo(42L);
            assertThat(eventCaptor.getValue().totalSegmentCount()).isEqualTo(2);
            assertThat(eventCaptor.getValue().snapshotVersion()).startsWith("sha256:");
        }
    }

    @Nested
    @DisplayName("read paths")
    class ReadPathTests {

        @Test
        @DisplayName("getSegmentsForCall returns db segments when archive is empty")
        void getSegmentsForCall_dbOnly_returnsDbSegments() {
            List<CallTranscriptSegment> dbSegments = List.of(segment("NURSE", "hello", 10L, 20L, "SRC", 1L, LocalDateTime.now()));
            when(callTranscriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID)).thenReturn(dbSegments);
            when(callTranscriptArchiveService.getArchivedSegments(CALL_ID)).thenReturn(List.of());

            assertThat(service.getSegmentsForCall(CALL_ID)).containsExactlyElementsOf(dbSegments);
        }

        @Test
        @DisplayName("getSegmentsForCall merges archive and db segments without duplicates and sorts them")
        void getSegmentsForCall_mergeAndSorts() {
            LocalDateTime now = LocalDateTime.now();
            CallTranscriptSegment archived = segment("PATIENT", "hello", 100L, 200L, "SRC", 2L, now.minusSeconds(5));
            CallTranscriptSegment duplicateDb = segment("PATIENT", "hello", 100L, 200L, "SRC", 2L, now);
            CallTranscriptSegment dbOnly = segment("NURSE", "follow up", 300L, 400L, "SRC", 3L, now.plusSeconds(5));

            when(callTranscriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID)).thenReturn(List.of(duplicateDb, dbOnly));
            when(callTranscriptArchiveService.getArchivedSegments(CALL_ID)).thenReturn(List.of(archived));

            List<CallTranscriptSegment> result = service.getSegmentsForCall(CALL_ID);

            assertThat(result).hasSize(2);
            assertThat(result.get(0).getText()).isEqualTo("hello");
            assertThat(result.get(1).getText()).isEqualTo("follow up");
        }

        @Test
        @DisplayName("countSegments returns merged count when archive exists")
        void countSegments_whenArchived_returnsMergedCount() {
            when(callTranscriptSegmentRepository.countByCallId(CALL_ID)).thenReturn(1L);
            when(callTranscriptArchiveService.isArchived(CALL_ID)).thenReturn(true);
            when(callTranscriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID))
                    .thenReturn(List.of(segment("NURSE", "db", 20L, 30L, "SRC", 1L, LocalDateTime.now())));
            when(callTranscriptArchiveService.getArchivedSegments(CALL_ID))
                    .thenReturn(List.of(segment("PATIENT", "archived", 10L, 20L, "SRC", 2L, LocalDateTime.now())));

            assertThat(service.countSegments(CALL_ID)).isEqualTo(2L);
        }

        @Test
        @DisplayName("hasTranscriptAccess checks repository first then archive service")
        void hasTranscriptAccess_checksDbThenArchive() {
            when(callTranscriptSegmentRepository.existsByCallIdAndActorUserId(CALL_ID, 5L)).thenReturn(false);
            when(callTranscriptArchiveService.hasArchivedTranscriptAccess(CALL_ID, 5L)).thenReturn(true);

            assertThat(service.hasTranscriptAccess(CALL_ID, 5L)).isTrue();
        }

        @Test
        @DisplayName("buildTranscriptTextForSummary labels unknown speakers and enforces max transcript length")
        void buildTranscriptTextForSummary_formatsAndCapsLength() {
            CallTranscriptSegment unknownSpeaker = segment(null, "first line", 10L, 20L, "SRC", 1L, LocalDateTime.now());
            CallTranscriptSegment large = segment("NURSE", "x".repeat(15990), 30L, 40L, "SRC", 1L, LocalDateTime.now());
            when(callTranscriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID)).thenReturn(List.of(unknownSpeaker, large));
            when(callTranscriptArchiveService.getArchivedSegments(CALL_ID)).thenReturn(List.of());

            String transcript = service.buildTranscriptTextForSummary(CALL_ID);

            assertThat(transcript).startsWith("[UNKNOWN] first line");
            assertThat(transcript).doesNotContain("[NURSE]");
            assertThat(transcript.length()).isLessThanOrEqualTo(16000);
        }

        @Test
        @DisplayName("summary snapshot keeps text count and version from one segment read")
        void captureSummarySnapshot_isStableAndVersioned() {
            final List<CallTranscriptSegment> captured = List.of(
                    segment("PATIENT", "first", 10L, 20L, "SRC", 1L, LocalDateTime.now()),
                    segment("NURSE", "second", 30L, 40L, "SRC", 2L, LocalDateTime.now()));
            when(callTranscriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID))
                    .thenReturn(captured);
            when(callTranscriptArchiveService.getArchivedSegments(CALL_ID)).thenReturn(List.of());

            final CallTranscriptService.TranscriptSnapshot snapshot =
                    service.captureSummarySnapshot(CALL_ID);

            assertThat(snapshot.segmentCount()).isEqualTo(2);
            assertThat(snapshot.transcriptText()).contains("[PATIENT] first", "[NURSE] second");
            assertThat(snapshot.version()).startsWith("sha256:");
            verify(callTranscriptSegmentRepository).findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID);
        }

        @Test
        @DisplayName("authoritative snapshots fail closed when archive content is incomplete")
        void captureIndexingSnapshot_incompleteArchive_failsClosed() {
            when(callTranscriptSegmentRepository
                    .findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID))
                    .thenReturn(List.of());
            when(callTranscriptArchiveService.getArchivedSegments(CALL_ID))
                    .thenReturn(List.of());
            when(callTranscriptArchiveService.isArchived(CALL_ID)).thenReturn(true);
            when(callTranscriptArchiveService.getArchivedSegmentCount(CALL_ID))
                    .thenReturn(3L);

            assertThatThrownBy(() -> service.captureIndexingSnapshot(CALL_ID))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("archive");
        }
    }

    @Nested
    @DisplayName("passthrough operations")
    class PassthroughOperationTests {

        @Test
        @DisplayName("archiveIfEligible trims callId and delegates atomic archival")
        void archiveIfEligible_delegates() {
            when(callTranscriptArchiveService.archiveIfEligible(CALL_ID)).thenReturn(true);

            assertThat(service.archiveIfEligible("  " + CALL_ID + "  ")).isTrue();
        }

        @Test
        @DisplayName("isArchived delegates to archive service")
        void isArchived_delegates() {
            when(callTranscriptArchiveService.isArchived(CALL_ID)).thenReturn(true);

            assertThat(service.isArchived(CALL_ID)).isTrue();
        }

        @Test
        @DisplayName("purgeForCall deletes transcript rows and archives")
        void purgeForCall_deletesBothSources() {
            when(callTranscriptSegmentRepository.deleteByCallId(CALL_ID)).thenReturn(3L);
            when(callTranscriptArchiveService.purgeArchiveForCall(CALL_ID)).thenReturn(1L);

            Map<String, Long> result = service.purgeForCall("  " + CALL_ID + "  ");

            assertThat(result).containsEntry("deletedTranscriptSegments", 3L);
            assertThat(result).containsEntry("deletedTranscriptArchives", 1L);
        }

        @Test
        @DisplayName("purgeForCall returns zeros when callId is blank")
        void purgeForCall_blankCallId_returnsZeros() {
            assertThat(service.purgeForCall(" ")).containsEntry("deletedTranscriptSegments", 0L);
            verify(callTranscriptSegmentRepository, never()).deleteByCallId(nullable(String.class));
        }
    }
}
