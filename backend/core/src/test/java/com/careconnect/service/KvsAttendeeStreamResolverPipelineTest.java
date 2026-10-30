package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.model.CallAttendee;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineRequest;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.GetMediaPipelineResponse;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipeline;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaPipelineStatus;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.MediaStreamPipeline;

/**
 * Covers the media-stream-pipeline readiness wait, timeout and interruption paths of {@link
 * KvsAttendeeStreamResolver}. The Chime media pipelines client is a Mockito mock and all waits use
 * millisecond intervals.
 */
@DisplayName("KvsAttendeeStreamResolver pipeline wait and timeout")
class KvsAttendeeStreamResolverPipelineTest {

    private static final String CALL_ID = "call-1";
    private static final String MEETING_ID = "meeting-uuid";
    private static final String PIPELINE_ID = "media-pipeline-1";
    private static final String ARN = "arn:aws:kinesisvideo:us-east-1:1:stream/a/1";

    private final Logger resolverLogger =
            (Logger) LoggerFactory.getLogger(KvsAttendeeStreamResolver.class);
    private Level originalLevel;

    private KvsAttendeeStreamRegistry registry;
    private KvsPoolStreamDiscoveryService discovery;
    private KvsStreamPoolService poolService;
    private ChimeSdkMediaPipelinesClient pipelinesClient;
    private KvsAttendeeStreamResolver resolver;

    @BeforeEach
    void setUp() {
        originalLevel = resolverLogger.getLevel();
        resolverLogger.setLevel(Level.DEBUG);
        registry = mock(KvsAttendeeStreamRegistry.class);
        discovery = mock(KvsPoolStreamDiscoveryService.class);
        poolService = mock(KvsStreamPoolService.class);
        pipelinesClient = mock(ChimeSdkMediaPipelinesClient.class);
        lenient().when(registry.getMappings(anyString())).thenReturn(Map.of());
        resolver = new KvsAttendeeStreamResolver(registry, discovery, poolService);
        ReflectionTestUtils.setField(resolver, "pipelinesClient", pipelinesClient);
        ReflectionTestUtils.setField(resolver, "discoveryTimeoutMs", 40L);
        ReflectionTestUtils.setField(resolver, "pollIntervalMs", 5L);
    }

    @AfterEach
    void tearDown() {
        resolverLogger.setLevel(originalLevel);
        // Clear any interrupt flag a test left behind.
        Thread.interrupted();
    }

    private static CallAttendee attendee(final String chimeId) {
        final CallAttendee attendee = new CallAttendee();
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId(chimeId);
        attendee.setJoinedAt(LocalDateTime.now());
        return attendee;
    }

    private static GetMediaPipelineResponse pipelineWithStatus(final MediaPipelineStatus status) {
        return GetMediaPipelineResponse.builder()
                .mediaPipeline(
                        MediaPipeline.builder()
                                .mediaStreamPipeline(
                                        MediaStreamPipeline.builder().status(status).build())
                                .build())
                .build();
    }

    @Test
    @DisplayName("null or empty attendee list resolves to no mappings")
    void emptyAttendees_returnEmptyMap() {
        assertThat(resolver.resolve(CALL_ID, null, PIPELINE_ID, MEETING_ID)).isEmpty();
        assertThat(resolver.resolve(CALL_ID, List.of(), PIPELINE_ID, MEETING_ID)).isEmpty();
        verifyNoInteractions(pipelinesClient);
    }

    @Test
    @DisplayName("an InProgress pipeline starts discovery and returns the mapped stream")
    void inProgressPipeline_thenMappingFound() {
        when(pipelinesClient.getMediaPipeline(any(GetMediaPipelineRequest.class)))
                .thenReturn(pipelineWithStatus(MediaPipelineStatus.IN_PROGRESS));
        when(registry.getStreamArn(CALL_ID, "att-1")).thenReturn(ARN);

        final Map<String, String> result =
                resolver.resolve(CALL_ID, List.of(attendee("att-1")), PIPELINE_ID, MEETING_ID);

        assertThat(result).containsEntry("att-1", ARN);
    }

    @Test
    @DisplayName("a failed pipeline stops the readiness wait and discovery registers the stream")
    void failedPipeline_discoveryRegistersMapping() {
        when(pipelinesClient.getMediaPipeline(any(GetMediaPipelineRequest.class)))
                .thenReturn(pipelineWithStatus(MediaPipelineStatus.FAILED));
        when(poolService.isIngestMode()).thenReturn(true);
        when(registry.getStreamArn(CALL_ID, "att-1")).thenReturn(null).thenReturn(ARN);

        final Map<String, String> result =
                resolver.resolve(CALL_ID, List.of(attendee("att-1")), PIPELINE_ID, MEETING_ID);

        assertThat(result).containsEntry("att-1", ARN);
        verify(discovery).discoverAndRegister(eq(CALL_ID), eq(MEETING_ID), anyList());
    }

    @Test
    @DisplayName("mappings that appear after the final poll are still returned")
    void mappingAppearsAfterDeadline_isReturned() {
        ReflectionTestUtils.setField(resolver, "pipelinesClient", null);
        ReflectionTestUtils.setField(resolver, "pollIntervalMs", 60L);
        when(registry.getStreamArn(CALL_ID, "att-1"))
                .thenReturn(null)
                .thenReturn(null)
                .thenReturn(ARN);

        final Map<String, String> result =
                resolver.resolve(CALL_ID, List.of(attendee("att-1")), PIPELINE_ID, MEETING_ID);

        assertThat(result).containsEntry("att-1", ARN);
        verify(discovery, never()).discoverAndRegister(anyString(), anyString(), anyList());
    }

    @Test
    @DisplayName("times out when the pipeline never becomes ready and no stream is mapped")
    void pipelineNeverReady_timesOut() {
        when(pipelinesClient.getMediaPipeline(any(GetMediaPipelineRequest.class)))
                .thenThrow(new RuntimeException("NotFound"))
                .thenReturn(GetMediaPipelineResponse.builder().build())
                .thenReturn(
                        GetMediaPipelineResponse.builder()
                                .mediaPipeline(MediaPipeline.builder().build())
                                .build())
                .thenReturn(pipelineWithStatus(MediaPipelineStatus.INITIALIZING));

        assertThatThrownBy(
                        () ->
                                resolver.resolve(
                                        CALL_ID, List.of(attendee("att-1")), PIPELINE_ID, MEETING_ID))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Timed out waiting for KVS stream assignments");
        verify(pipelinesClient, atLeastOnce()).getMediaPipeline(any(GetMediaPipelineRequest.class));
    }

    @Test
    @DisplayName("blank pipeline id skips the readiness wait")
    void blankPipelineId_skipsWait() {
        when(registry.getStreamArn(CALL_ID, "att-1")).thenReturn(ARN);

        resolver.resolve(CALL_ID, List.of(attendee("att-1")), " ", MEETING_ID);
        resolver.resolve(CALL_ID, List.of(attendee("att-1")), null, MEETING_ID);

        verifyNoInteractions(pipelinesClient);
    }

    @Test
    @DisplayName("an interrupted sleep restores the interrupt flag and keeps polling until timeout")
    void interruptedSleep_restoresFlag() {
        ReflectionTestUtils.setField(resolver, "pipelinesClient", null);
        ReflectionTestUtils.setField(resolver, "pollIntervalMs", 0L);
        Thread.currentThread().interrupt();

        assertThatThrownBy(
                        () ->
                                resolver.resolve(
                                        CALL_ID, List.of(attendee("att-1")), PIPELINE_ID, MEETING_ID))
                .isInstanceOf(IllegalStateException.class);
        assertThat(Thread.interrupted()).isTrue();
    }
}
