package com.careconnect.service;

import java.io.OutputStream;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
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

/** Exports archived KVS fragments for one Chime attendee stream. */
@Service
public class KvsArchivedMediaExportService {

  private static final Logger log = LoggerFactory.getLogger(KvsArchivedMediaExportService.class);

  private static final long EXPORT_WINDOW_PADDING_SECONDS = 10L;

  @Autowired(required = false)
  private KinesisVideoClient kinesisVideoClient;

  /**
   * Exports the attendee stream fragment range to a temporary WebM/MKV file.
   *
   * @return temporary raw media path
   */
  public Path exportAttendeeRange(
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
    final List<String> fragmentNumbers = listFragmentNumbers(region, streamArn, paddedStart, paddedEnd);
    if (fragmentNumbers.isEmpty()) {
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
          "Exported {} KVS fragments streamArn={} output={}",
          fragmentNumbers.size(),
          streamArn,
          output);
    }
    return output;
  }

  private List<String> listFragmentNumbers(
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
          .sorted(Comparator.comparing(Fragment::serverTimestamp))
          .map(Fragment::fragmentNumber)
          .filter(fragmentNumber -> fragmentNumber != null && !fragmentNumber.isBlank())
          .toList();
    }
  }

  private KinesisVideoArchivedMediaClient archivedClient(final Region region, final String endpoint) {
    return KinesisVideoArchivedMediaClient.builder()
        .region(region)
        .endpointOverride(URI.create(endpoint))
        .credentialsProvider(kinesisVideoClient.serviceClientConfiguration().credentialsProvider())
        .build();
  }

  private static String regionFromArn(final String arn) {
    final String[] parts = arn.split(":");
    if (parts.length > 3 && parts[3] != null && !parts[3].isBlank()) {
      return parts[3];
    }
    return "us-east-1";
  }
}
