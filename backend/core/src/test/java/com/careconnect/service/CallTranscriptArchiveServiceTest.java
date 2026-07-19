package com.careconnect.service;

import com.careconnect.model.CallRecording;
import com.careconnect.model.CallTranscriptArchive;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.CallTranscriptArchiveRepository;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("CallTranscriptArchiveService Tests")
class CallTranscriptArchiveServiceTest {

    @Mock
    private CallTranscriptArchiveRepository archiveRepository;

    @Mock
    private CallTranscriptSegmentRepository segmentRepository;

    @Mock
    private CallRecordingRepository callRecordingRepository;

    @Mock
    private ObjectMapper objectMapper;

    @Mock
    private S3StorageService s3StorageService;

    @InjectMocks
    private CallTranscriptArchiveService service;

    private static final String CALL_ID = "call-abc-123";

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(service, "s3StorageService", s3StorageService);
        ReflectionTestUtils.setField(service, "archiveEnabled", true);
        ReflectionTestUtils.setField(service, "minArchiveSegments", 600);
        ReflectionTestUtils.setField(service, "minArchiveChars", 120000);
        ReflectionTestUtils.setField(service, "deleteDbRows", true);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private CallTranscriptSegment buildSegment(String text, Long actorUserId) {
        CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setCallId(CALL_ID);
        segment.setSpeakerLabel("Speaker");
        segment.setText(text);
        segment.setStartMs(0L);
        segment.setEndMs(1000L);
        segment.setSource("chime");
        segment.setActorUserId(actorUserId);
        segment.setOccurredAt(LocalDateTime.of(2026, 3, 17, 10, 0, 0));
        return segment;
    }

    private List<CallTranscriptSegment> buildLargeSegmentList(int count, int charsPerSegment) {
        List<CallTranscriptSegment> segments = new ArrayList<>();
        String text = "A".repeat(charsPerSegment);
        for (int i = 0; i < count; i++) {
            CallTranscriptSegment segment = buildSegment(text, (long) (i % 3 + 1));
            segment.setId((long) i + 1);
            segments.add(segment);
        }
        return segments;
    }

    private boolean archiveCaptured(List<CallTranscriptSegment> segments) {
        when(segmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID))
                .thenReturn(segments);
        org.mockito.Mockito.lenient()
                .when(s3StorageService.download(anyString()))
                .thenReturn(new byte[]{1, 2, 3});
        return service.archiveIfEligible(CALL_ID, segments);
    }

    private CallTranscriptArchive buildArchive(String callId, String storageKey,
                                                String participantUserIds) {
        CallTranscriptArchive archive = new CallTranscriptArchive();
        archive.setCallId(callId);
        archive.setStorageProvider("S3");
        archive.setStorageKey(storageKey);
        archive.setSegmentCount(100);
        archive.setTranscriptChars(50000);
        archive.setParticipantUserIds(participantUserIds);
        archive.setArchivedAt(LocalDateTime.now());
        return archive;
    }

    // ════════════════════════════════════════════════════════════════════════
    //  isArchived
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("isArchived Tests")
    class IsArchivedTests {

        @Test
        @DisplayName("Returns true when archive exists for callId")
        void returnsTrueWhenArchiveExists() {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(true);

            assertThat(service.isArchived(CALL_ID)).isTrue();
        }

        @Test
        @DisplayName("Returns false when no archive exists")
        void returnsFalseWhenNoArchiveExists() {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);

            assertThat(service.isArchived(CALL_ID)).isFalse();
        }

        @Test
        @DisplayName("Returns false for null callId")
        void returnsFalseForNullCallId() {
            assertThat(service.isArchived(null)).isFalse();
        }

        @Test
        @DisplayName("Returns false for blank callId")
        void returnsFalseForBlankCallId() {
            assertThat(service.isArchived("   ")).isFalse();
        }

        @Test
        @DisplayName("Returns false for empty callId")
        void returnsFalseForEmptyCallId() {
            assertThat(service.isArchived("")).isFalse();
        }

        @Test
        @DisplayName("Trims callId before lookup")
        void trimsCallIdBeforeLookup() {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(true);

            assertThat(service.isArchived("  " + CALL_ID + "  ")).isTrue();
            verify(archiveRepository).existsByCallId(CALL_ID);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  hasArchivedTranscriptAccess
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("hasArchivedTranscriptAccess Tests")
    class HasArchivedTranscriptAccessTests {

        @Test
        @DisplayName("Returns true when user is a participant")
        void returnsTrueWhenUserIsParticipant() {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "key", "1,2,3");
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));

            assertThat(service.hasArchivedTranscriptAccess(CALL_ID, 2L)).isTrue();
        }

        @Test
        @DisplayName("Returns false when user is not a participant")
        void returnsFalseWhenUserIsNotParticipant() {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "key", "1,2,3");
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));

            assertThat(service.hasArchivedTranscriptAccess(CALL_ID, 99L)).isFalse();
        }

        @Test
        @DisplayName("Returns false for null callId")
        void returnsFalseForNullCallId() {
            assertThat(service.hasArchivedTranscriptAccess(null, 1L)).isFalse();
        }

        @Test
        @DisplayName("Returns false for null userId")
        void returnsFalseForNullUserId() {
            assertThat(service.hasArchivedTranscriptAccess(CALL_ID, null)).isFalse();
        }

        @Test
        @DisplayName("Returns false when no archive found")
        void returnsFalseWhenNoArchiveFound() {
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            assertThat(service.hasArchivedTranscriptAccess(CALL_ID, 1L)).isFalse();
        }

        @Test
        @DisplayName("Returns false when participantUserIds is null")
        void returnsFalseWhenParticipantUserIdsIsNull() {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "key", null);
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));

            assertThat(service.hasArchivedTranscriptAccess(CALL_ID, 1L)).isFalse();
        }

        @Test
        @DisplayName("Returns false when participantUserIds is blank")
        void returnsFalseWhenParticipantUserIdsIsBlank() {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "key", "   ");
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));

            assertThat(service.hasArchivedTranscriptAccess(CALL_ID, 1L)).isFalse();
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  getArchivedSegmentCount
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getArchivedSegmentCount Tests")
    class GetArchivedSegmentCountTests {

        @Test
        @DisplayName("Returns segment count from archive")
        void returnsSegmentCountFromArchive() {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "key", "1");
            archive.setSegmentCount(250);
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));

            assertThat(service.getArchivedSegmentCount(CALL_ID)).isEqualTo(250L);
        }

        @Test
        @DisplayName("Returns 0 when no archive found")
        void returnsZeroWhenNoArchiveFound() {
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            assertThat(service.getArchivedSegmentCount(CALL_ID)).isEqualTo(0L);
        }

        @Test
        @DisplayName("Returns 0 for null callId")
        void returnsZeroForNullCallId() {
            assertThat(service.getArchivedSegmentCount(null)).isEqualTo(0L);
        }

        @Test
        @DisplayName("Returns 0 for blank callId")
        void returnsZeroForBlankCallId() {
            assertThat(service.getArchivedSegmentCount("  ")).isEqualTo(0L);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  getArchivedSegments
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getArchivedSegments Tests")
    class GetArchivedSegmentsTests {

        @Test
        @DisplayName("Returns empty list for null callId")
        void returnsEmptyListForNullCallId() {
            assertThat(service.getArchivedSegments(null)).isEmpty();
        }

        @Test
        @DisplayName("Returns empty list for blank callId")
        void returnsEmptyListForBlankCallId() {
            assertThat(service.getArchivedSegments("  ")).isEmpty();
        }

        @Test
        @DisplayName("Returns empty list when s3StorageService is null")
        void returnsEmptyListWhenS3Null() {
            ReflectionTestUtils.setField(service, "s3StorageService", null);

            assertThat(service.getArchivedSegments(CALL_ID)).isEmpty();
        }

        @Test
        @DisplayName("Returns empty list when no archive found")
        void returnsEmptyListWhenNoArchiveFound() {
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.empty());

            assertThat(service.getArchivedSegments(CALL_ID)).isEmpty();
        }

        @Test
        @DisplayName("Returns segments from S3 successfully")
        void returnsSegmentsFromS3() throws Exception {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "transcripts/data.json", "1,2");
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));

            String json = "[{\"speakerLabel\":\"Speaker 1\",\"text\":\"Hello world\","
                    + "\"startMs\":0,\"endMs\":1000,\"source\":\"chime\","
                    + "\"actorUserId\":1,\"occurredAt\":\"2026-03-17T10:00:00\"}]";
            byte[] bytes = json.getBytes();
            when(s3StorageService.download("transcripts/data.json")).thenReturn(bytes);

            // Use real ObjectMapper for deserialization
            ObjectMapper realMapper = new ObjectMapper();
            realMapper.findAndRegisterModules();
            ReflectionTestUtils.setField(service, "objectMapper", realMapper);

            List<CallTranscriptSegment> result = service.getArchivedSegments(CALL_ID);

            assertThat(result).hasSize(1);
            assertThat(result.get(0).getText()).isEqualTo("Hello world");
            assertThat(result.get(0).getCallId()).isEqualTo(CALL_ID);
            assertThat(result.get(0).getSpeakerLabel()).isEqualTo("Speaker 1");
        }

        @Test
        @DisplayName("Skips segments with null or blank text")
        void skipsSegmentsWithNullOrBlankText() throws Exception {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "key.json", "1");
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));

            String json = "[{\"speakerLabel\":\"S1\",\"text\":\"\",\"startMs\":0,\"endMs\":100,"
                    + "\"source\":\"chime\",\"actorUserId\":1,\"occurredAt\":null},"
                    + "{\"speakerLabel\":\"S2\",\"text\":\"Valid text\",\"startMs\":100,\"endMs\":200,"
                    + "\"source\":\"chime\",\"actorUserId\":1,\"occurredAt\":null}]";
            byte[] bytes = json.getBytes();
            when(s3StorageService.download("key.json")).thenReturn(bytes);

            ObjectMapper realMapper = new ObjectMapper();
            realMapper.findAndRegisterModules();
            ReflectionTestUtils.setField(service, "objectMapper", realMapper);

            List<CallTranscriptSegment> result = service.getArchivedSegments(CALL_ID);

            assertThat(result).hasSize(1);
            assertThat(result.get(0).getText()).isEqualTo("Valid text");
        }

        @Test
        @DisplayName("Returns empty list on S3 download exception")
        void returnsEmptyListOnS3Exception() {
            CallTranscriptArchive archive = buildArchive(CALL_ID, "key.json", "1");
            when(archiveRepository.findTopByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(archive));
            when(s3StorageService.download("key.json"))
                    .thenThrow(new RuntimeException("S3 unavailable"));

            assertThat(service.getArchivedSegments(CALL_ID)).isEmpty();
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  archiveIfEligible
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("archiveIfEligible Tests")
    class ArchiveIfEligibleTests {

        @Test
        @DisplayName("Returns false for null callId")
        void returnsFalseForNullCallId() {
            assertThat(service.archiveIfEligible(null, List.of())).isFalse();
        }

        @Test
        @DisplayName("Returns false for blank callId")
        void returnsFalseForBlankCallId() {
            assertThat(service.archiveIfEligible("  ", List.of())).isFalse();
        }

        @Test
        @DisplayName("Returns false when archive is disabled")
        void returnsFalseWhenArchiveDisabled() {
            ReflectionTestUtils.setField(service, "archiveEnabled", false);

            assertThat(service.archiveIfEligible(CALL_ID, List.of(buildSegment("text", 1L))))
                    .isFalse();
        }

        @Test
        @DisplayName("Returns false when s3StorageService is null")
        void returnsFalseWhenS3Null() {
            ReflectionTestUtils.setField(service, "s3StorageService", null);

            assertThat(service.archiveIfEligible(CALL_ID, List.of(buildSegment("text", 1L))))
                    .isFalse();
        }

        @Test
        @DisplayName("Returns false when archive already exists")
        void returnsFalseWhenArchiveAlreadyExists() {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(true);

            assertThat(service.archiveIfEligible(CALL_ID, List.of(buildSegment("text", 1L))))
                    .isFalse();
        }

        @Test
        @DisplayName("Returns false for null segments list")
        void returnsFalseForNullSegments() {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);

            assertThat(service.archiveIfEligible(CALL_ID, null)).isFalse();
        }

        @Test
        @DisplayName("Returns false for empty segments list")
        void returnsFalseForEmptySegments() {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);

            assertThat(service.archiveIfEligible(CALL_ID, Collections.emptyList())).isFalse();
        }

        @Test
        @DisplayName("Returns false when below both thresholds")
        void returnsFalseWhenBelowBothThresholds() {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            // 5 segments with 10 chars each = 50 chars, well below both thresholds
            List<CallTranscriptSegment> segments = buildLargeSegmentList(5, 10);

            assertThat(archiveCaptured(segments)).isFalse();
        }

        @Test
        @DisplayName("Returns true when segment count exceeds threshold")
        void returnsTrueWhenSegmentCountExceedsThreshold() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            // 601 segments, each 10 chars - exceeds minSegmentsForArchive (600)
            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);

            assertThat(archiveCaptured(segments)).isTrue();
            verify(archiveRepository).save(any(CallTranscriptArchive.class));
            verify(s3StorageService).upload(anyString(), any(byte[].class), eq("application/json"));
        }

        @Test
        @DisplayName("Returns true when chars exceed threshold")
        void returnsTrueWhenCharsExceedThreshold() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            // 100 segments, each 1300 chars = 130000 chars, exceeds minCharsForArchive (120000)
            List<CallTranscriptSegment> segments = buildLargeSegmentList(100, 1300);

            assertThat(archiveCaptured(segments)).isTrue();
            verify(archiveRepository).save(any(CallTranscriptArchive.class));
        }

        @Test
        @DisplayName("Deletes DB segments after archiving when deleteDbAfterArchive is true")
        void deletesDbSegmentsWhenConfigured() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);

            archiveCaptured(segments);

            verify(segmentRepository).acquireArchiveLock(CALL_ID);
            verify(segmentRepository).deleteByCallIdAndIdIn(eq(CALL_ID), any());
        }

        @Test
        @DisplayName("Does not save or delete when uploaded checksum does not match")
        void checksumMismatchPreservesCapturedSegments() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});
            when(s3StorageService.download(anyString())).thenReturn(new byte[]{9, 9, 9});
            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);
            when(segmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(CALL_ID))
                    .thenReturn(segments);

            assertThat(service.archiveIfEligible(CALL_ID, segments)).isFalse();

            verify(archiveRepository, never()).save(any());
            verify(segmentRepository, never()).deleteByCallIdAndIdIn(anyString(), any());
        }

        @Test
        @DisplayName("Does not delete DB segments when deleteDbAfterArchive is false")
        void doesNotDeleteDbSegmentsWhenNotConfigured() throws Exception {
            ReflectionTestUtils.setField(service, "deleteDbRows", false);
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);

            archiveCaptured(segments);

            verify(segmentRepository, never()).deleteByCallIdAndIdIn(anyString(), any());
        }

        @Test
        @DisplayName("Uses recording S3 prefix when available")
        void usesRecordingS3PrefixWhenAvailable() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            CallRecording recording = new CallRecording();
            recording.setS3Prefix("recordings/call-abc-123/20260317_100000/");
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                    .thenReturn(Optional.of(recording));
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);

            archiveCaptured(segments);

            ArgumentCaptor<String> keyCaptor = ArgumentCaptor.forClass(String.class);
            verify(s3StorageService).upload(keyCaptor.capture(), any(byte[].class),
                    eq("application/json"));
            assertThat(keyCaptor.getValue())
                    .startsWith("recordings/call-abc-123/20260317_100000/transcripts/");
        }

        @Test
        @DisplayName("Saves archive with correct metadata")
        void savesArchiveWithCorrectMetadata() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);

            archiveCaptured(segments);

            ArgumentCaptor<CallTranscriptArchive> captor =
                    ArgumentCaptor.forClass(CallTranscriptArchive.class);
            verify(archiveRepository).save(captor.capture());

            CallTranscriptArchive saved = captor.getValue();
            assertThat(saved.getCallId()).isEqualTo(CALL_ID);
            assertThat(saved.getStorageProvider()).isEqualTo("S3");
            assertThat(saved.getSegmentCount()).isEqualTo(601);
            assertThat(saved.getTranscriptChars()).isEqualTo(601 * 10);
            assertThat(saved.getSha256Checksum()).isNotEmpty();
            assertThat(saved.getArchivedAt()).isNotNull();
        }

        @Test
        @DisplayName("Returns false on S3 upload exception")
        void returnsFalseOnS3UploadException() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});
            when(s3StorageService.upload(anyString(), any(byte[].class), anyString()))
                    .thenThrow(new RuntimeException("Upload failed"));

            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);

            assertThat(archiveCaptured(segments)).isFalse();
            verify(archiveRepository, never()).save(any());
        }

        @Test
        @DisplayName("Builds participant user IDs from segments correctly")
        void buildsParticipantUserIdsCorrectly() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            // Segments with actorUserId 1, 2, 3 (repeating pattern from helper)
            List<CallTranscriptSegment> segments = buildLargeSegmentList(601, 10);

            archiveCaptured(segments);

            ArgumentCaptor<CallTranscriptArchive> captor =
                    ArgumentCaptor.forClass(CallTranscriptArchive.class);
            verify(archiveRepository).save(captor.capture());

            String participantIds = captor.getValue().getParticipantUserIds();
            assertThat(participantIds).contains("1");
            assertThat(participantIds).contains("2");
            assertThat(participantIds).contains("3");
        }

        @Test
        @DisplayName("Excludes segments with null or blank text from char count")
        void excludesNullTextFromCharCount() throws Exception {
            when(archiveRepository.existsByCallId(CALL_ID)).thenReturn(false);
            when(callRecordingRepository.findTopByCallIdOrderByStartedAtDesc(anyString()))
                    .thenReturn(Optional.empty());
            when(objectMapper.writeValueAsBytes(any())).thenReturn(new byte[]{1, 2, 3});

            List<CallTranscriptSegment> segments = new ArrayList<>();
            // 600 segments with valid text (201 chars each = 120600 total > 120000)
            for (int i = 0; i < 600; i++) {
                segments.add(buildSegment("B".repeat(201), 1L));
            }
            // Add some segments with null/blank text
            CallTranscriptSegment nullTextSeg = buildSegment(null, 1L);
            segments.add(nullTextSeg);
            CallTranscriptSegment blankTextSeg = buildSegment("   ", 1L);
            segments.add(blankTextSeg);

            for (int i = 0; i < segments.size(); i++) {
                segments.get(i).setId((long) i + 1);
            }
            archiveCaptured(segments);

            ArgumentCaptor<CallTranscriptArchive> captor =
                    ArgumentCaptor.forClass(CallTranscriptArchive.class);
            verify(archiveRepository).save(captor.capture());

            // Char count should not include null/blank segments
            assertThat(captor.getValue().getTranscriptChars()).isEqualTo(600 * 201);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  purgeArchiveForCall
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("purgeArchiveForCall Tests")
    class PurgeArchiveTests {

        @Test
        @DisplayName("Returns 0 for null callId")
        void returnsZeroForNullCallId() {
            assertThat(service.purgeArchiveForCall(null)).isEqualTo(0L);
        }

        @Test
        @DisplayName("Returns 0 for blank callId")
        void returnsZeroForBlankCallId() {
            assertThat(service.purgeArchiveForCall("  ")).isEqualTo(0L);
        }

        @Test
        @DisplayName("Returns 0 when no archives found")
        void returnsZeroWhenNoArchivesFound() {
            when(archiveRepository.findByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Collections.emptyList());

            assertThat(service.purgeArchiveForCall(CALL_ID)).isEqualTo(0L);
        }

        @Test
        @DisplayName("Deletes S3 objects and DB records")
        void deletesS3ObjectsAndDbRecords() {
            CallTranscriptArchive archive1 = buildArchive(CALL_ID, "key1.json", "1");
            CallTranscriptArchive archive2 = buildArchive(CALL_ID, "key2.json", "1,2");
            when(archiveRepository.findByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(List.of(archive1, archive2));
            when(archiveRepository.deleteByCallId(CALL_ID)).thenReturn(2L);

            long result = service.purgeArchiveForCall(CALL_ID);

            assertThat(result).isEqualTo(2L);
            verify(s3StorageService).deleteFile("key1.json");
            verify(s3StorageService).deleteFile("key2.json");
            verify(archiveRepository).deleteByCallId(CALL_ID);
        }

        @Test
        @DisplayName("Skips archives with null or blank storage key")
        void skipsArchivesWithNullStorageKey() {
            CallTranscriptArchive archive1 = buildArchive(CALL_ID, null, "1");
            CallTranscriptArchive archive2 = buildArchive(CALL_ID, "  ", "1");
            CallTranscriptArchive archive3 = buildArchive(CALL_ID, "valid-key.json", "1");
            when(archiveRepository.findByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(List.of(archive1, archive2, archive3));
            when(archiveRepository.deleteByCallId(CALL_ID)).thenReturn(3L);

            service.purgeArchiveForCall(CALL_ID);

            verify(s3StorageService).deleteFile("valid-key.json");
            // Should only call deleteFile once (for the valid key)
        }

        @Test
        @DisplayName("Continues purge even if S3 delete fails")
        void continuesPurgeOnS3DeleteFailure() {
            CallTranscriptArchive archive1 = buildArchive(CALL_ID, "key1.json", "1");
            CallTranscriptArchive archive2 = buildArchive(CALL_ID, "key2.json", "1");
            when(archiveRepository.findByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(List.of(archive1, archive2));
            when(archiveRepository.deleteByCallId(CALL_ID)).thenReturn(2L);

            // First S3 delete fails
            doThrow(new RuntimeException("S3 error"))
                    .when(s3StorageService).deleteFile("key1.json");

            long result = service.purgeArchiveForCall(CALL_ID);

            assertThat(result).isEqualTo(2L);
            // Both delete attempts made, DB purge still happens
            verify(s3StorageService).deleteFile("key2.json");
            verify(archiveRepository).deleteByCallId(CALL_ID);
        }

        @Test
        @DisplayName("Handles purge when s3StorageService is null")
        void handlesPurgeWhenS3Null() {
            ReflectionTestUtils.setField(service, "s3StorageService", null);
            when(archiveRepository.deleteByCallId(CALL_ID)).thenReturn(1L);

            long result = service.purgeArchiveForCall(CALL_ID);

            assertThat(result).isEqualTo(1L);
            // S3 delete should not be called
        }

        @Test
        @DisplayName("Trims callId before purge")
        void trimsCallIdBeforePurge() {
            when(archiveRepository.findByCallIdOrderByArchivedAtDesc(CALL_ID))
                    .thenReturn(Collections.emptyList());

            service.purgeArchiveForCall("  " + CALL_ID + "  ");

            verify(archiveRepository).findByCallIdOrderByArchivedAtDesc(CALL_ID);
        }
    }
}
