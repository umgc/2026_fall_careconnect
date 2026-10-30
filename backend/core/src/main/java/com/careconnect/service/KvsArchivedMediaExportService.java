package com.careconnect.service;

import java.io.OutputStream;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoClient;
import software.amazon.awssdk.services.kinesisvideo.model.APIName;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.KinesisVideoArchivedMediaClient;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.Fragment;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.FragmentSelector;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.FragmentSelectorType;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.TimestampRange;

/**
 * Exports archived KVS fragments for one Chime attendee stream into a single media file.
 */
@Service
public class KvsArchivedMediaExportService {

    private static final Logger log = LoggerFactory.getLogger(KvsArchivedMediaExportService.class);

    private static final long EXPORT_WINDOW_PADDING_SECONDS = 10L;

    @Autowired(required = false)
    private KinesisVideoClient kinesisVideoClient;

    private static String regionFromArn(final String arn) {
        final String[] parts = arn.split(":");
        if (parts.length > 3 && parts[3] != null && !parts[3].isBlank()) {
            return parts[3];
        }
        return "us-east-1";
    }

    /**
     * Lists fragments in the window ({@code SERVER_TIMESTAMP}), concatenates them via {@code
     * GetMediaForFragmentList}, and writes one temporary WebM/MKV file for ffmpeg → WAV.
     *
     * <p>The fragment query is padded so a fragment that began just before {@code start} (or clock
     * skew between our timestamps and KVS's) does not cut off the first words. The padding is for
     * selection only: the returned clip's trim window, measured from the first fragment's server
     * timestamp, is exactly {@code [start, end)}, and the transcoder decodes nothing outside it.
     *
     * @return temporary raw media file and the slice of it covering {@code [start, end)}
     */
    public KvsAudioClip exportAttendeeRange(
            final String streamArn,
            final Instant start,
            final Instant end) throws Exception {
        if (kinesisVideoClient == null) {
            throw new IllegalStateException("KinesisVideoClient is not available");
        }
        if (streamArn == null || streamArn.isBlank()) {
            throw new IllegalArgumentException("KVS stream ARN is required");
        }
        if (start == null || end == null || !end.isAfter(start)) {
            throw new IllegalArgumentException("Valid KVS export start/end timestamps are required");
        }

        final Region region = Region.of(regionFromArn(streamArn));
        final Instant paddedStart = start.minusSeconds(EXPORT_WINDOW_PADDING_SECONDS);
        final Instant paddedEnd = end.plusSeconds(EXPORT_WINDOW_PADDING_SECONDS);
        final List<Fragment> fragments = listFragments(region, streamArn, paddedStart, paddedEnd);
        if (fragments.isEmpty()) {
            if (log.isWarnEnabled()) {
                log.warn(
                        "No KVS fragments found streamArn={} start={} end={} paddedStart={} paddedEnd={}",
                        streamArn,
                        start,
                        end,
                        paddedStart,
                        paddedEnd);
            }
            throw new IllegalStateException("No KVS fragments found for attendee stream " + streamArn);
        }
        final Instant mediaStart = fragments.get(0).serverTimestamp();
        final long[] trim = trimWindowMs(mediaStart, start, end);
        if (trim.length == 0) {
            throw new IllegalStateException("No KVS fragments inside window for attendee stream " + streamArn);
        }
        final long trimStartMs = trim[0];
        final long trimEndMs = trim[1];
        final List<String> fragmentNumbers = fragments.stream().map(Fragment::fragmentNumber).toList();

        final String mediaEndpoint =
                kinesisVideoClient
                        .getDataEndpoint(
                                GetDataEndpointRequest.builder()
                                        .streamARN(streamArn)
                                        .apiName(APIName.GET_MEDIA_FOR_FRAGMENT_LIST)
                                        .build())
                        .dataEndpoint();

        final Path output = Files.createTempFile("careconnect-kvs-", ".mkv");
        try (KinesisVideoArchivedMediaClient mediaClient = archivedClient(region, mediaEndpoint);
             ResponseInputStream<GetMediaForFragmentListResponse> media =
                     mediaClient.getMediaForFragmentList(
                             GetMediaForFragmentListRequest.builder()
                                     .streamARN(streamArn)
                                     .fragments(fragmentNumbers)
                                     .build());
             OutputStream out = Files.newOutputStream(output)) {
            media.transferTo(out);
        }

        if (log.isInfoEnabled()) {
            log.info(
                    "Exported {} KVS fragments streamArn={} output={} mediaStart={} trimMs=[{}, {})",
                    fragmentNumbers.size(),
                    streamArn,
                    output,
                    mediaStart,
                    trimStartMs,
                    trimEndMs);
        }
        return new KvsAudioClip(output, trimStartMs, trimEndMs);
    }

    /**
     * Where {@code [start, end)} lies in media whose first fragment began at {@code mediaStart}:
     * {@code {startMs, endMs}} from the start of the file, or an empty array when every fetched
     * fragment is after the window (only padding was found). A window that starts before the
     * first fragment begins at 0: there is no earlier audio to cut.
     */
    static long[] trimWindowMs(final Instant mediaStart, final Instant start, final Instant end) {
        final long startMs = Math.max(0L, Duration.between(mediaStart, start).toMillis());
        final long endMs = Duration.between(mediaStart, end).toMillis();
        return endMs > startMs ? new long[] {startMs, endMs} : new long[0];
    }

    private List<Fragment> listFragments(
            final Region region,
            final String streamArn,
            final Instant start,
            final Instant end) {
        final String listEndpoint =
                kinesisVideoClient
                        .getDataEndpoint(
                                GetDataEndpointRequest.builder()
                                        .streamARN(streamArn)
                                        .apiName(APIName.LIST_FRAGMENTS)
                                        .build())
                        .dataEndpoint();

        try (KinesisVideoArchivedMediaClient listClient = archivedClient(region, listEndpoint)) {
            return listClient
                    .listFragments(
                            ListFragmentsRequest.builder()
                                    .streamARN(streamArn)
                                    .fragmentSelector(
                                            FragmentSelector.builder()
                                                    .fragmentSelectorType(FragmentSelectorType.SERVER_TIMESTAMP)
                                                    .timestampRange(
                                                            TimestampRange.builder()
                                                                    .startTimestamp(start)
                                                                    .endTimestamp(end)
                                                                    .build())
                                                    .build())
                                    .build())
                    .fragments()
                    .stream()
                    .filter(fragment -> fragment.serverTimestamp() != null)
                    .filter(fragment -> fragment.fragmentNumber() != null && !fragment.fragmentNumber().isBlank())
                    .sorted(Comparator.comparing(Fragment::serverTimestamp))
                    .toList();
        }
    }

    /** Package-private so tests can supply a mocked client; production builds a real one. */
    KinesisVideoArchivedMediaClient archivedClient(final Region region, final String endpoint) {
        return KinesisVideoArchivedMediaClient.builder()
                .region(region)
                .endpointOverride(URI.create(endpoint))
                .credentialsProvider(kinesisVideoClient.serviceClientConfiguration().credentialsProvider())
                .build();
    }
}
