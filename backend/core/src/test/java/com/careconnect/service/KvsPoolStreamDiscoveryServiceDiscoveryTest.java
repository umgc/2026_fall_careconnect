package com.careconnect.service;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;
import org.slf4j.LoggerFactory;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoClient;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoServiceClientConfiguration;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointRequest;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointResponse;
import software.amazon.awssdk.services.kinesisvideo.model.ListStreamsRequest;
import software.amazon.awssdk.services.kinesisvideo.model.ListStreamsResponse;
import software.amazon.awssdk.services.kinesisvideo.model.StreamInfo;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.KinesisVideoArchivedMediaClient;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.KinesisVideoArchivedMediaClientBuilder;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.Fragment;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsResponse;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.RETURNS_SELF;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Exercises the polling discovery loop of {@link KvsPoolStreamDiscoveryService}: ListStreams,
 * candidate selection, ListFragments, GetMediaForFragmentList and attendee registration. Every
 * Kinesis Video client is a Mockito mock; the archived-media client builder is replaced with a
 * static mock so no endpoint is ever contacted.
 */
@DisplayName("KvsPoolStreamDiscoveryService discovery loop")
class KvsPoolStreamDiscoveryServiceDiscoveryTest {

    private static final String CALL_ID = "call-1";
    private static final String MEETING_ID = "11111111-2222-3333-4444-555555555555";
    private static final String ATTENDEE_A = "attendee-aaa";
    private static final String ATTENDEE_B = "attendee-bbb";
    private static final String POOL_PREFIX = "ChimeMediaPipelines-dev";
    private static final String ENDPOINT = "https://b-test.kinesisvideo.us-east-1.amazonaws.com";

    private final Logger serviceLogger =
            (Logger) LoggerFactory.getLogger(KvsPoolStreamDiscoveryService.class);
    private Level originalLevel;

    private KvsAttendeeStreamRegistry registry;
    private KvsStreamPoolService poolService;
    private KinesisVideoClient kinesisVideoClient;
    private KinesisVideoArchivedMediaClient archivedClient;
    private KinesisVideoArchivedMediaClientBuilder builder;
    private KvsPoolStreamDiscoveryService service;

    @BeforeEach
    void setUp() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.DEBUG);

        registry = new KvsAttendeeStreamRegistry();
        poolService = mock(KvsStreamPoolService.class);
        lenient().when(poolService.isIngestMode()).thenReturn(true);
        lenient().when(poolService.getStreamPoolRegion()).thenReturn("us-east-1");
        lenient().when(poolService.getStreamPoolListStreamsPrefix()).thenReturn(POOL_PREFIX);

        kinesisVideoClient = mock(KinesisVideoClient.class);
        lenient()
                .when(kinesisVideoClient.getDataEndpoint(any(GetDataEndpointRequest.class)))
                .thenReturn(GetDataEndpointResponse.builder().dataEndpoint(ENDPOINT).build());
        lenient()
                .when(kinesisVideoClient.serviceClientConfiguration())
                .thenReturn(mock(KinesisVideoServiceClientConfiguration.class));

        archivedClient = mock(KinesisVideoArchivedMediaClient.class);
        builder = mock(KinesisVideoArchivedMediaClientBuilder.class, RETURNS_SELF);
        lenient().when(builder.build()).thenReturn(archivedClient);

        service = new KvsPoolStreamDiscoveryService(registry, poolService);
        ReflectionTestUtils.setField(service, "kinesisVideoClient", kinesisVideoClient);
    }

    @AfterEach
    void restoreLogger() {
        serviceLogger.setLevel(originalLevel);
    }

    private static StreamInfo stream(final String name, final Instant created) {
        return StreamInfo.builder()
                .streamName(name)
                .streamARN("arn:aws:kinesisvideo:us-east-1:123456789012:stream/" + name + "/1")
                .creationTime(created)
                .build();
    }

    private void listStreamsReturns(final List<StreamInfo> pool, final List<StreamInfo> chime) {
        when(kinesisVideoClient.listStreams(any(ListStreamsRequest.class)))
                .thenAnswer(
                        invocation -> {
                            final ListStreamsRequest request = invocation.getArgument(0);
                            final String prefix =
                                    request.streamNameCondition() == null
                                            ? ""
                                            : request.streamNameCondition().comparisonValue();
                            return ListStreamsResponse.builder()
                                    .streamInfoList(POOL_PREFIX.equals(prefix) ? pool : chime)
                                    .build();
                        });
    }

    private static ResponseInputStream<GetMediaForFragmentListResponse> media(final byte[] bytes) {
        return new ResponseInputStream<>(
                GetMediaForFragmentListResponse.builder().build(),
                AbortableInputStream.create(new ByteArrayInputStream(bytes)));
    }

    private static byte[] fragmentFor(final String meetingId, final String attendeeId) {
        return ("EBML" + meetingId + "|" + attendeeId + "|audio").getBytes(StandardCharsets.UTF_8);
    }

    private void fragmentsReturn(final String... fragmentNumbers) {
        final List<Fragment> fragments = new ArrayList<>();
        for (final String number : fragmentNumbers) {
            fragments.add(Fragment.builder().fragmentNumber(number).build());
        }
        when(archivedClient.listFragments(any(ListFragmentsRequest.class)))
                .thenReturn(ListFragmentsResponse.builder().fragments(fragments).build());
    }

    @Test
    @DisplayName("returns without AWS calls when ingest mode is off or arguments are missing")
    void guardClauses_skipDiscovery() {
        when(poolService.isIngestMode()).thenReturn(false);
        service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));

        when(poolService.isIngestMode()).thenReturn(true);
        service.discoverAndRegister(null, MEETING_ID, List.of(ATTENDEE_A));
        service.discoverAndRegister(" ", MEETING_ID, List.of(ATTENDEE_A));
        service.discoverAndRegister(CALL_ID, null, List.of(ATTENDEE_A));
        service.discoverAndRegister(CALL_ID, " ", List.of(ATTENDEE_A));
        service.discoverAndRegister(CALL_ID, MEETING_ID, null);
        service.discoverAndRegister(CALL_ID, MEETING_ID, List.of());

        ReflectionTestUtils.setField(service, "kinesisVideoClient", null);
        service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));

        verifyNoInteractions(kinesisVideoClient);
    }

    @Test
    @DisplayName("skips discovery when the stream-pool ARN has no region")
    void blankRegion_skipsDiscovery() {
        when(poolService.getStreamPoolRegion()).thenReturn("");

        service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));

        verifyNoInteractions(kinesisVideoClient);
    }

    @Test
    @DisplayName("skips discovery when every attendee is blank or already mapped")
    void noPendingAttendees_skipsListStreams() {
        registry.register(CALL_ID, ATTENDEE_A, "arn:existing");
        final List<String> attendees = new ArrayList<>();
        attendees.add(ATTENDEE_A);
        attendees.add(null);
        attendees.add(" ");

        service.discoverAndRegister(CALL_ID, MEETING_ID, attendees);

        verify(kinesisVideoClient, never()).listStreams(any(ListStreamsRequest.class));
    }

    @Test
    @DisplayName("registers the attendee whose id appears in a pool-stream fragment")
    void matchingFragment_registersAttendee() {
        final StreamInfo poolStream = stream("ChimeMediaPipelines-dev-abc", Instant.now());
        listStreamsReturns(List.of(poolStream), List.of());
        fragmentsReturn("1", "2");
        when(archivedClient.getMediaForFragmentList(any(GetMediaForFragmentListRequest.class)))
                .thenReturn(media(new byte[0]))
                .thenReturn(media(fragmentFor(MEETING_ID, ATTENDEE_A)));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);

            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
            // Second poll: attendee already mapped, nothing pending.
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        assertThat(registry.getStreamArn(CALL_ID, ATTENDEE_A)).isEqualTo(poolStream.streamARN());
        verify(kinesisVideoClient).listStreams(any(ListStreamsRequest.class));
    }

    @Test
    @DisplayName("falls back to ChimeSDK streams when the pool prefix lists nothing")
    void emptyPool_fallsBackToChimeSdkPrefix() {
        final StreamInfo chimeStream = stream("ChimeSDK-xyz", Instant.now());
        listStreamsReturns(List.of(), List.of(chimeStream));
        when(archivedClient.listFragments(any(ListFragmentsRequest.class)))
                .thenReturn(ListFragmentsResponse.builder().fragments(List.of()).build());

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);

            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
            // Second poll on the same call does not warn twice but still scans.
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        final ArgumentCaptor<ListStreamsRequest> captor =
                ArgumentCaptor.forClass(ListStreamsRequest.class);
        verify(kinesisVideoClient, atLeastOnce()).listStreams(captor.capture());
        assertThat(captor.getAllValues())
                .extracting(r -> r.streamNameCondition().comparisonValue())
                .contains(POOL_PREFIX, "ChimeSDK");
        assertThat(registry.getMappings(CALL_ID)).isEmpty();
    }

    @Test
    @DisplayName("fragments without the meeting id leave attendees unmapped")
    void fragmentsWithoutMeetingId_doNotRegister() {
        listStreamsReturns(List.of(stream("ChimeMediaPipelines-dev-1", Instant.now())), List.of());
        fragmentsReturn("1");
        when(archivedClient.getMediaForFragmentList(any(GetMediaForFragmentListRequest.class)))
                .thenReturn(media("unrelated-bytes".getBytes(StandardCharsets.UTF_8)));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        assertThat(registry.getMappings(CALL_ID)).isEmpty();
    }

    @Test
    @DisplayName("meeting bytes seen without an attendee match keep scanning remaining fragments")
    void meetingIdWithoutAttendee_scansAllFragments() {
        listStreamsReturns(List.of(stream("ChimeMediaPipelines-dev-1", Instant.now())), List.of());
        fragmentsReturn("1", " ", "2");
        when(archivedClient.getMediaForFragmentList(any(GetMediaForFragmentListRequest.class)))
                .thenReturn(media(fragmentFor(MEETING_ID, "someone-else")))
                .thenReturn(media(fragmentFor(MEETING_ID.replace("-", ""), "other")));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        verify(archivedClient, org.mockito.Mockito.times(2))
                .getMediaForFragmentList(any(GetMediaForFragmentListRequest.class));
        assertThat(registry.getMappings(CALL_ID)).isEmpty();
    }

    @Test
    @DisplayName("fragment lists with only blank fragment numbers read no media")
    void blankFragmentNumbers_readNoMedia() {
        listStreamsReturns(List.of(stream("ChimeMediaPipelines-dev-1", Instant.now())), List.of());
        fragmentsReturn(" ");

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        verify(archivedClient, never())
                .getMediaForFragmentList(any(GetMediaForFragmentListRequest.class));
    }

    @Test
    @DisplayName("access-denied and generic fragment read failures are swallowed")
    void fragmentReadFailures_areSwallowed() {
        listStreamsReturns(
                List.of(
                        stream("ChimeMediaPipelines-dev-1", Instant.now()),
                        stream("ChimeMediaPipelines-dev-2", Instant.now())),
                List.of());
        when(archivedClient.listFragments(any(ListFragmentsRequest.class)))
                .thenThrow(new RuntimeException("User is not authorized to perform ListFragments"))
                .thenThrow(new RuntimeException("connection reset"));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        assertThat(registry.getMappings(CALL_ID)).isEmpty();
        verify(archivedClient, org.mockito.Mockito.times(2))
                .listFragments(any(ListFragmentsRequest.class));
    }

    @Test
    @DisplayName("ListStreams failures (denied, 403, generic) yield no candidates")
    void listStreamsFailures_yieldNoCandidates() {
        when(kinesisVideoClient.listStreams(any(ListStreamsRequest.class)))
                .thenThrow(new RuntimeException("AccessDeniedException"))
                .thenThrow(new RuntimeException("Status Code: 403"))
                .thenThrow(new RuntimeException((String) null))
                .thenThrow(new RuntimeException("throttled"));

        service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        service.discoverAndRegister("call-2", MEETING_ID, List.of(ATTENDEE_A));

        assertThat(registry.getMappings(CALL_ID)).isEmpty();
        verify(kinesisVideoClient, org.mockito.Mockito.times(4))
                .listStreams(any(ListStreamsRequest.class));
    }

    @Test
    @DisplayName("blank pool prefix lists without a name condition")
    void blankPoolPrefix_listsWithoutCondition() {
        when(poolService.getStreamPoolListStreamsPrefix()).thenReturn("");
        when(kinesisVideoClient.listStreams(any(ListStreamsRequest.class)))
                .thenReturn(ListStreamsResponse.builder().streamInfoList(List.of()).build());

        service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));

        final ArgumentCaptor<ListStreamsRequest> captor =
                ArgumentCaptor.forClass(ListStreamsRequest.class);
        verify(kinesisVideoClient, org.mockito.Mockito.times(2)).listStreams(captor.capture());
        assertThat(captor.getAllValues().get(0).streamNameCondition()).isNull();
    }

    @Test
    @DisplayName("streams with blank names or already-mapped ARNs are skipped")
    void invalidOrMappedStreams_areSkipped() {
        final StreamInfo mapped = stream("ChimeMediaPipelines-dev-mapped", Instant.now());
        registry.register(CALL_ID, "other-attendee", mapped.streamARN());
        final List<StreamInfo> pool =
                List.of(
                        StreamInfo.builder().streamName("x").streamARN(null).creationTime(Instant.now()).build(),
                        StreamInfo.builder().streamName("x").streamARN(" ").creationTime(Instant.now()).build(),
                        StreamInfo.builder().streamName(null).streamARN("arn:a").creationTime(Instant.now()).build(),
                        StreamInfo.builder().streamName(" ").streamARN("arn:b").creationTime(Instant.now()).build(),
                        mapped);
        listStreamsReturns(pool, List.of());

        service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));

        verify(kinesisVideoClient, never()).getDataEndpoint(any(GetDataEndpointRequest.class));
    }

    @Test
    @DisplayName("stops scanning once every pending attendee has been registered")
    void allAttendeesMatched_stopsScanning() {
        final StreamInfo first = stream("ChimeMediaPipelines-dev-1", Instant.now());
        final StreamInfo second =
                stream("ChimeMediaPipelines-dev-2", Instant.now().minus(1, ChronoUnit.MINUTES));
        listStreamsReturns(List.of(first, second), List.of());
        fragmentsReturn("1");
        when(archivedClient.getMediaForFragmentList(any(GetMediaForFragmentListRequest.class)))
                .thenReturn(media(fragmentFor(MEETING_ID, ATTENDEE_A)));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        assertThat(registry.getStreamArn(CALL_ID, ATTENDEE_A)).isEqualTo(first.streamARN());
        verify(kinesisVideoClient, never())
                .getDataEndpoint(
                        eq(
                                GetDataEndpointRequest.builder()
                                        .streamName(second.streamName())
                                        .apiName(
                                                software.amazon.awssdk.services.kinesisvideo.model
                                                        .APIName.LIST_FRAGMENTS)
                                        .build()));
    }

    @Test
    @DisplayName("rotates the scan window across polls when more than 16 old streams exist")
    void manyStaleStreams_rotateScanWindow() {
        final List<StreamInfo> pool = new ArrayList<>();
        final Instant old = Instant.now().minus(2, ChronoUnit.HOURS);
        for (int i = 0; i < 20; i++) {
            pool.add(stream("ChimeMediaPipelines-dev-" + i, old.minusSeconds(i)));
        }
        pool.add(StreamInfo.builder().streamName("no-time").streamARN(null).build());
        listStreamsReturns(pool, List.of());
        when(archivedClient.listFragments(any(ListFragmentsRequest.class)))
                .thenReturn(ListFragmentsResponse.builder().build());

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A, ATTENDEE_B));
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A, ATTENDEE_B));
        }

        @SuppressWarnings("unchecked")
        final Map<String, Integer> offsets =
                (Map<String, Integer>) ReflectionTestUtils.getField(service, "scanOffsetsByCallId");
        assertThat(offsets).containsEntry(CALL_ID, 16 % 21);
    }

    @Test
    @DisplayName("an empty media stream is treated as no fragment bytes")
    void emptyMediaStream_isIgnored() {
        listStreamsReturns(List.of(stream("ChimeMediaPipelines-dev-1", Instant.now())), List.of());
        fragmentsReturn("1");
        when(archivedClient.getMediaForFragmentList(any(GetMediaForFragmentListRequest.class)))
                .thenReturn(media(new byte[0]));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        assertThat(registry.getMappings(CALL_ID)).isEmpty();
    }

    @Test
    @DisplayName("prioritizeRecentStreams orders newest first and handles empty input")
    void prioritizeRecentStreams_ordersNewestFirst() {
        final StreamInfo older = stream("a", Instant.now().minusSeconds(60));
        final StreamInfo newer = stream("b", Instant.now());
        final StreamInfo noTime = StreamInfo.builder().streamName("c").build();

        assertThat(KvsPoolStreamDiscoveryService.prioritizeRecentStreams(null, 5)).isEmpty();
        assertThat(KvsPoolStreamDiscoveryService.prioritizeRecentStreams(List.of(), 5)).isEmpty();
        assertThat(KvsPoolStreamDiscoveryService.prioritizeRecentStreams(List.of(older), 0))
                .isEmpty();
        assertThat(
                        KvsPoolStreamDiscoveryService.prioritizeRecentStreams(
                                List.of(noTime, older, newer), 2))
                .containsExactly(newer, older);
    }

    @Test
    @DisplayName("streamNameFromArn extracts the stream segment and tolerates bad input")
    void streamNameFromArn_parsesArn() {
        assertThat(KvsPoolStreamDiscoveryService.streamNameFromArn(null)).isEmpty();
        assertThat(KvsPoolStreamDiscoveryService.streamNameFromArn(" ")).isEmpty();
        assertThat(KvsPoolStreamDiscoveryService.streamNameFromArn("arn:aws:other")).isEmpty();
        assertThat(
                        KvsPoolStreamDiscoveryService.streamNameFromArn(
                                "arn:aws:kinesisvideo:us-east-1:1:stream/name-1/123"))
                .isEqualTo("name-1");
        assertThat(
                        KvsPoolStreamDiscoveryService.streamNameFromArn(
                                "arn:aws:kinesisvideo:us-east-1:1:stream/name-2"))
                .isEqualTo("name-2");
    }

    @Test
    @DisplayName("readUpTo returns empty bytes for a null stream and copies partial reads")
    void readUpTo_handlesNullAndPartialStreams() throws Exception {
        final java.lang.reflect.Method readUpTo =
                KvsPoolStreamDiscoveryService.class.getDeclaredMethod(
                        "readUpTo", InputStream.class, int.class);
        readUpTo.setAccessible(true);

        assertThat((byte[]) readUpTo.invoke(null, null, 8)).isEmpty();
        assertThat((byte[]) readUpTo.invoke(null, new ByteArrayInputStream(new byte[] {1, 2}), 8))
                .containsExactly(1, 2);
        assertThat((byte[]) readUpTo.invoke(null, new ByteArrayInputStream(new byte[] {1, 2, 3}), 2))
                .containsExactly(1, 2);
    }

    @Test
    @DisplayName("no debug summaries are logged when debug is disabled")
    void debugDisabled_stillScans() throws IOException {
        serviceLogger.setLevel(Level.ERROR);
        listStreamsReturns(List.of(stream("ChimeMediaPipelines-dev-1", Instant.now())), List.of());
        when(archivedClient.listFragments(any(ListFragmentsRequest.class)))
                .thenThrow(new RuntimeException("boom"));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics =
                mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            service.discoverAndRegister(CALL_ID, MEETING_ID, List.of(ATTENDEE_A));
        }

        verify(kinesisVideoClient, atLeastOnce()).getDataEndpoint(any(GetDataEndpointRequest.class));
        verify(builder, atLeastOnce()).endpointOverride(any());
    }
}
