package com.careconnect.service;

import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.kinesisvideo.model.StreamInfo;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("KvsStreamPoolService Tests")
class KvsStreamPoolServiceTest {

    private static final String POOL_ARN =
            "arn:aws:chime:us-east-1:123456789012:media-pipeline-kinesis-video-stream-pool/dev";

    @Nested
    @DisplayName("Ingest mode (stream pool ARN)")
    class IngestModeTests {

        @Test
        @DisplayName("SPEAKER-029: isIngestMode true when stream pool ARN is configured")
        void ingestMode_configured() {
            final KvsStreamPoolService service = KvsStreamPoolService.forTest(true, POOL_ARN);

            assertThat(service.isIngestMode()).isTrue();
            assertThat(service.isEnabled()).isTrue();
            assertThat(service.getStreamPoolArn()).isEqualTo(POOL_ARN);
            assertThat(service.getStreamPoolName()).isEqualTo("dev");
            assertThat(service.getStreamPoolListStreamsPrefix())
                    .isEqualTo("ChimeMediaPipelines-dev");
            assertThat(service.getStreamPoolRegion()).isEqualTo("us-east-1");
        }

        @Test
        @DisplayName("SPEAKER-027: enabled without pool ARN is not active")
        void enabledWithoutPoolArn_notActive() {
            final KvsStreamPoolService empty = KvsStreamPoolService.forTest(true, "");

            assertThat(empty.isIngestMode()).isFalse();
            assertThat(empty.isEnabled()).isFalse();
        }

        @Test
        @DisplayName("SPEAKER-020: disabled service is not active even with pool ARN")
        void disabled_notActive() {
            final KvsStreamPoolService service = KvsStreamPoolService.forTest(false, POOL_ARN);

            assertThat(service.isIngestMode()).isFalse();
            assertThat(service.isEnabled()).isFalse();
        }
    }

    @Nested
    @DisplayName("Pool ARN parsing")
    class PoolArnParsingTests {

        @Test
        @DisplayName("SPEAKER-048: streamNameFromArn extracts stream name segment")
        void streamNameFromArn_parses() {
            assertThat(
                            KvsPoolStreamDiscoveryService.streamNameFromArn(
                                    "arn:aws:kinesisvideo:us-east-1:123:stream/ChimeSDKPool_abc/12345"))
                    .isEqualTo("ChimeSDKPool_abc");
        }

        @Test
        @DisplayName("SPEAKER-049: prioritizeRecentStreams keeps newest streams only")
        void prioritizeRecentStreams_sortsAndLimits() {
            final StreamInfo older =
                    StreamInfo.builder()
                            .streamName("old")
                            .streamARN("arn:aws:kinesisvideo:us-east-1:1:stream/old/1")
                            .creationTime(Instant.parse("2026-01-01T00:00:00Z"))
                            .build();
            final StreamInfo newer =
                    StreamInfo.builder()
                            .streamName("new")
                            .streamARN("arn:aws:kinesisvideo:us-east-1:1:stream/new/1")
                            .creationTime(Instant.parse("2026-06-29T16:00:00Z"))
                            .build();

            assertThat(KvsPoolStreamDiscoveryService.prioritizeRecentStreams(List.of(older, newer), 1))
                    .extracting(StreamInfo::streamName)
                    .containsExactly("new");
        }
    }
}
