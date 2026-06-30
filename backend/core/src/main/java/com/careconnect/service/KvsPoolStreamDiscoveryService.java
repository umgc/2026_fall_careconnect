package com.careconnect.service;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoClient;
import software.amazon.awssdk.services.kinesisvideo.model.APIName;
import software.amazon.awssdk.services.kinesisvideo.model.ComparisonOperator;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointRequest;
import software.amazon.awssdk.services.kinesisvideo.model.ListStreamsRequest;
import software.amazon.awssdk.services.kinesisvideo.model.StreamInfo;
import software.amazon.awssdk.services.kinesisvideo.model.StreamNameCondition;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.KinesisVideoArchivedMediaClient;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.Fragment;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.FragmentSelector;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.FragmentSelectorType;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.TimestampRange;

/**
 * Discovers Chime-assigned KVS stream ARNs by polling pool streams and reading fragment metadata
 * (F5.5d / Option C). No EventBridge or inbound webhook required.
 */
@Service
public class KvsPoolStreamDiscoveryService {

    private static final Logger log = LoggerFactory.getLogger(KvsPoolStreamDiscoveryService.class);

    private static final int MAX_FRAGMENT_BYTES = 65_536;
    private static final long FRAGMENT_LOOKBACK_SECONDS = 300L;
    private static final long RECENT_STREAM_WINDOW_MINUTES = 30L;
    private static final int MAX_STREAMS_PER_POLL = 16;
    private static final int MAX_FRAGMENTS_PER_STREAM = 5;
    private static final String CHIME_STREAM_PREFIX = "ChimeSDK";

    private final KvsAttendeeStreamRegistry registry;
    private final KvsStreamPoolService kvsStreamPoolService;

    private final Set<String> zeroPoolStreamWarnedCallIds = ConcurrentHashMap.newKeySet();
    private final Set<String> poolStreamsSeenCallIds = ConcurrentHashMap.newKeySet();
    private final Map<String, Integer> scanOffsetsByCallId = new ConcurrentHashMap<>();

    @Autowired(required = false)
    private KinesisVideoClient kinesisVideoClient;

    public KvsPoolStreamDiscoveryService(
            final KvsAttendeeStreamRegistry registry,
            final KvsStreamPoolService kvsStreamPoolService) {
        this.registry = registry;
        this.kvsStreamPoolService = kvsStreamPoolService;
    }

    /**
     * Lists KVS streams in the configured pool and registers attendee→stream mappings when fragment
     * metadata matches the active meeting and attendees.
     */
    public void discoverAndRegister(
            final String callId, final String meetingId, final Collection<String> attendeeIds) {
        if (!kvsStreamPoolService.isIngestMode()
                || kinesisVideoClient == null
                || callId == null
                || callId.isBlank()
                || meetingId == null
                || meetingId.isBlank()
                || attendeeIds == null
                || attendeeIds.isEmpty()) {
            return;
        }

        final String poolRegion = kvsStreamPoolService.getStreamPoolRegion();
        if (poolRegion.isBlank()) {
            return;
        }

        final Set<String> pending = new HashSet<>(attendeeIds);
        pending.removeIf(id -> id == null || id.isBlank());
        pending.removeIf(id -> registry.getStreamArn(callId, id) != null);
        if (pending.isEmpty()) {
            return;
        }

        final Region region = Region.of(poolRegion);
        final String poolListPrefix = kvsStreamPoolService.getStreamPoolListStreamsPrefix();
        final List<StreamInfo> poolStreams = listStreamsWithPrefix(poolListPrefix);
        final List<StreamInfo> allCandidates = selectCandidateStreams(poolStreams);
        if (poolStreams.isEmpty() && zeroPoolStreamWarnedCallIds.add(callId)) {
            if (log.isWarnEnabled()) {
                log.warn(
                        "KVS pool prefix '{}' returned 0 streams for callId={}. Chime creates pool"
                                + " streams only when IndividualAudio is active — keep both users unmuted"
                                + " and speaking. Legacy manual streams in the account are ignored.",
                        poolListPrefix,
                        callId);
            }
        } else if (!poolStreams.isEmpty() && poolStreamsSeenCallIds.add(callId) && log.isInfoEnabled()) {
            log.info(
                    "KVS pool streams visible for callId={} poolPrefix='{}' count={}",
                    callId,
                    poolListPrefix,
                    poolStreams.size());
        }

        final Instant recentCutoff = Instant.now().minus(RECENT_STREAM_WINDOW_MINUTES, ChronoUnit.MINUTES);
        final List<StreamInfo> recentCandidates = filterRecentStreams(allCandidates, recentCutoff);
        final List<StreamInfo> prioritized =
                prioritizeRecentStreams(
                        recentCandidates.isEmpty() ? allCandidates : recentCandidates,
                        Math.max(allCandidates.size(), MAX_STREAMS_PER_POLL));
        final List<StreamInfo> streams = rotateScanWindow(callId, prioritized, MAX_STREAMS_PER_POLL);

        int streamsWithFragments = 0;
        int streamsWithMeetingBytes = 0;

        if (log.isDebugEnabled()) {
            log.debug(
                    "KVS discovery poll callId={} meetingId={} poolStreams={} candidateStreams={}"
                            + " scanning={} pendingAttendees={}",
                    callId,
                    meetingId,
                    poolStreams.size(),
                    allCandidates.size(),
                    streams.size(),
                    pending.size());
        }
        for (final StreamInfo stream : streams) {
            if (pending.isEmpty()) {
                break;
            }
            final String streamArn = stream.streamARN();
            final String streamName = stream.streamName();
            if (streamArn == null
                    || streamArn.isBlank()
                    || streamName == null
                    || streamName.isBlank()) {
                continue;
            }
            if (registry.getMappings(callId).containsValue(streamArn)) {
                continue;
            }

            final FragmentScanResult scanResult =
                    tryRegisterFromStreamFragments(
                            region, streamName, streamArn, callId, meetingId, pending);
            if (scanResult.fragmentsRead() > 0) {
                streamsWithFragments++;
            }
            if (scanResult.meetingBytesSeen()) {
                streamsWithMeetingBytes++;
            }
        }

        if (!pending.isEmpty()
                && !streams.isEmpty()
                && streamsWithFragments == 0
                && log.isDebugEnabled()) {
            log.debug(
                    "KVS discovery poll found no readable fragments callId={} streamsScanned={}",
                    callId,
                    streams.size());
        } else if (!pending.isEmpty()
                && streamsWithFragments > 0
                && streamsWithMeetingBytes == 0
                && log.isDebugEnabled()) {
            log.debug(
                    "KVS fragments read for callId={} but meetingId={} not found in MKV metadata",
                    callId,
                    meetingId);
        }
    }

    private record FragmentScanResult(int fragmentsRead, boolean meetingBytesSeen) {}

    private FragmentScanResult tryRegisterFromStreamFragments(
            final Region region,
            final String streamName,
            final String streamArn,
            final String callId,
            final String meetingId,
            final Set<String> pending) {
        int fragmentsRead = 0;
        boolean meetingBytesSeen = false;
        for (final byte[] fragmentBytes : readRecentFragmentBytesList(region, streamName)) {
            if (fragmentBytes.length == 0) {
                continue;
            }
            fragmentsRead++;
            if (KvsFragmentMetadataReader.containsMeetingId(fragmentBytes, meetingId)) {
                meetingBytesSeen = true;
            }
            final boolean matched =
                    KvsFragmentMetadataReader.matchAttendeeId(fragmentBytes, meetingId, pending)
                            .map(
                                    attendeeId -> {
                                        registry.register(callId, attendeeId, streamArn);
                                        pending.remove(attendeeId);
                                        if (log.isInfoEnabled()) {
                                            log.info(
                                                    "Discovered KVS stream via polling callId={}"
                                                            + " attendeeId={} streamArn={} streamName={}",
                                                    callId,
                                                    attendeeId,
                                                    streamArn,
                                                    streamName);
                                        }
                                        return true;
                                    })
                            .orElse(false);
            if (matched) {
                return new FragmentScanResult(fragmentsRead, meetingBytesSeen);
            }
        }
        return new FragmentScanResult(fragmentsRead, meetingBytesSeen);
    }

    /**
     * In ingest mode only Chime pool streams (and legacy ChimeSDK streams) are scanned. Unrelated
     * manual KVS streams in the account are excluded.
     */
    private List<StreamInfo> selectCandidateStreams(final List<StreamInfo> poolStreams) {
        if (!poolStreams.isEmpty()) {
            return poolStreams;
        }
        return listStreamsWithPrefix(CHIME_STREAM_PREFIX);
    }

    private static List<StreamInfo> filterRecentStreams(
            final List<StreamInfo> streams, final Instant notBefore) {
        if (streams == null || streams.isEmpty()) {
            return List.of();
        }
        return streams.stream()
                .filter(
                        stream ->
                                stream.creationTime() != null
                                        && !stream.creationTime().isBefore(notBefore))
                .toList();
    }

    private List<StreamInfo> rotateScanWindow(
            final String callId, final List<StreamInfo> streams, final int windowSize) {
        if (streams == null || streams.isEmpty() || windowSize <= 0) {
            return List.of();
        }
        if (streams.size() <= windowSize) {
            return streams;
        }
        final int offset =
                scanOffsetsByCallId.merge(
                        callId,
                        0,
                        (current, ignored) -> (current + windowSize) % streams.size());
        final List<StreamInfo> rotated = new ArrayList<>(windowSize);
        for (int i = 0; i < windowSize; i++) {
            rotated.add(streams.get((offset + i) % streams.size()));
        }
        return rotated;
    }

    /** Prefer newest pool streams — stale ChimeSDK streams from prior calls accumulate in the account. */
    static List<StreamInfo> prioritizeRecentStreams(
            final List<StreamInfo> streams, final int maxStreams) {
        if (streams == null || streams.isEmpty() || maxStreams <= 0) {
            return List.of();
        }
        return streams.stream()
                .sorted(
                        Comparator.comparing(
                                StreamInfo::creationTime,
                                Comparator.nullsLast(Comparator.reverseOrder())))
                .limit(maxStreams)
                .toList();
    }

    private List<StreamInfo> listStreamsWithPrefix(final String prefix) {
        try {
            final ListStreamsRequest.Builder request =
                    ListStreamsRequest.builder().maxResults(1000);
            if (prefix != null && !prefix.isBlank()) {
                request.streamNameCondition(
                        StreamNameCondition.builder()
                                .comparisonOperator(ComparisonOperator.BEGINS_WITH)
                                .comparisonValue(prefix)
                                .build());
            }
            return kinesisVideoClient.listStreams(request.build()).streamInfoList();
        } catch (Exception e) {
            if (isAccessDenied(e)) {
                if (log.isWarnEnabled()) {
                    log.warn(
                            "KVS ListStreams denied for prefix '{}' — add kinesisvideo:ListStreams"
                                    + " on Resource '*', plus ListFragments/GetMedia on stream/*: {}",
                            prefix,
                            e.getMessage());
                }
            } else if (log.isWarnEnabled()) {
                log.warn("KVS ListStreams failed for prefix '{}': {}", prefix, e.getMessage());
            }
            return List.of();
        }
    }

    private static boolean isAccessDenied(final Exception e) {
        final String message = e.getMessage();
        return message != null
                && (message.contains("not authorized")
                        || message.contains("AccessDenied")
                        || message.contains("Status Code: 403"));
    }

    private List<byte[]> readRecentFragmentBytesList(final Region region, final String streamName) {
        try {
            final String listEndpoint =
                    kinesisVideoClient
                            .getDataEndpoint(
                                    GetDataEndpointRequest.builder()
                                            .streamName(streamName)
                                            .apiName(APIName.LIST_FRAGMENTS)
                                            .build())
                            .dataEndpoint();

            try (KinesisVideoArchivedMediaClient archivedClient =
                    KinesisVideoArchivedMediaClient.builder()
                            .region(region)
                            .endpointOverride(URI.create(listEndpoint))
                            .credentialsProvider(kinesisVideoClient.serviceClientConfiguration()
                                    .credentialsProvider())
                            .build()) {

                final Instant end = Instant.now();
                final Instant start = end.minusSeconds(FRAGMENT_LOOKBACK_SECONDS);
                final ListFragmentsResponse fragments =
                        archivedClient.listFragments(
                                ListFragmentsRequest.builder()
                                        .streamName(streamName)
                                        .fragmentSelector(
                                                FragmentSelector.builder()
                                                        .fragmentSelectorType(
                                                                FragmentSelectorType.SERVER_TIMESTAMP)
                                                        .timestampRange(
                                                                TimestampRange.builder()
                                                                        .startTimestamp(start)
                                                                        .endTimestamp(end)
                                                                        .build())
                                                        .build())
                                        .build());

                final List<Fragment> fragmentList = fragments.fragments();
                if (fragmentList == null || fragmentList.isEmpty()) {
                    return List.of();
                }

                final int from = Math.max(0, fragmentList.size() - MAX_FRAGMENTS_PER_STREAM);
                final List<String> fragmentNumbers = new ArrayList<>();
                for (int i = from; i < fragmentList.size(); i++) {
                    final String fragmentNumber = fragmentList.get(i).fragmentNumber();
                    if (fragmentNumber != null && !fragmentNumber.isBlank()) {
                        fragmentNumbers.add(fragmentNumber);
                    }
                }
                if (fragmentNumbers.isEmpty()) {
                    return List.of();
                }

                final String mediaEndpoint =
                        kinesisVideoClient
                                .getDataEndpoint(
                                        GetDataEndpointRequest.builder()
                                                .streamName(streamName)
                                                .apiName(APIName.GET_MEDIA)
                                                .build())
                                .dataEndpoint();

                try (KinesisVideoArchivedMediaClient mediaClient =
                        KinesisVideoArchivedMediaClient.builder()
                                .region(region)
                                .endpointOverride(URI.create(mediaEndpoint))
                                .credentialsProvider(
                                        kinesisVideoClient.serviceClientConfiguration()
                                                .credentialsProvider())
                                .build()) {

                    final List<byte[]> results = new ArrayList<>();
                    for (final String fragmentNumber : fragmentNumbers) {
                        try (ResponseInputStream<GetMediaForFragmentListResponse> media =
                                mediaClient.getMediaForFragmentList(
                                        GetMediaForFragmentListRequest.builder()
                                                .streamName(streamName)
                                                .fragments(fragmentNumber)
                                                .build())) {
                            final byte[] bytes = readUpTo(media, MAX_FRAGMENT_BYTES);
                            if (bytes.length > 0) {
                                results.add(bytes);
                            }
                        }
                    }
                    return results;
                }
            }
        } catch (Exception e) {
            if (isAccessDenied(e)) {
                if (log.isWarnEnabled()) {
                    log.warn(
                            "KVS fragment read denied for stream {} — ensure ListFragments,"
                                    + " GetDataEndpoint, GetMedia on stream/*: {}",
                            streamName,
                            e.getMessage());
                }
            } else if (log.isDebugEnabled()) {
                log.debug(
                        "Could not read KVS fragment metadata for stream {}: {}",
                        streamName,
                        e.getMessage());
            }
            return List.of();
        }
    }

    private static byte[] readUpTo(final InputStream input, final int maxBytes) throws IOException {
        if (input == null) {
            return new byte[0];
        }
        try (input) {
            final byte[] buffer = new byte[maxBytes];
            int offset = 0;
            int read;
            while (offset < maxBytes && (read = input.read(buffer, offset, maxBytes - offset)) >= 0) {
                offset += read;
            }
            if (offset == 0) {
                return new byte[0];
            }
            final byte[] result = new byte[offset];
            System.arraycopy(buffer, 0, result, 0, offset);
            return result;
        }
    }

    /** Visible for tests — KVS stream name from ARN. */
    static String streamNameFromArn(final String streamArn) {
        if (streamArn == null || streamArn.isBlank()) {
            return "";
        }
        final String marker = ":stream/";
        final int idx = streamArn.indexOf(marker);
        if (idx < 0) {
            return "";
        }
        final String rest = streamArn.substring(idx + marker.length());
        final int slash = rest.indexOf('/');
        return slash >= 0 ? rest.substring(0, slash) : rest;
    }
}
