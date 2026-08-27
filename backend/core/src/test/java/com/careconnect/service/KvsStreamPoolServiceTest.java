package com.careconnect.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("KvsStreamPoolService Tests")
class KvsStreamPoolServiceTest {

    private static final String VALID_ARN =
            "arn:aws:chime:us-east-1:123456789012:"
                    + "media-pipeline-kinesis-video-stream-pool/careconnect-dev-speaker";

    /** The literal default CloudFormation ships in 03-platform.yaml until a real pool is created. */
    private static final String PLACEHOLDER_ARN = "REPLACE_WITH_CHIME_KVS_STREAM_POOL_ARN";

    @Test
    @DisplayName("isIngestMode is false for the CloudFormation placeholder ARN")
    void isIngestMode_placeholderArn_isFalse() {
        final KvsStreamPoolService service = KvsStreamPoolService.forTest(true, PLACEHOLDER_ARN);
        assertThat(service.isIngestMode()).isFalse();
    }

    @Test
    @DisplayName("isIngestMode is false when the ARN is blank")
    void isIngestMode_blankArn_isFalse() {
        final KvsStreamPoolService service = KvsStreamPoolService.forTest(true, "");
        assertThat(service.isIngestMode()).isFalse();
    }

    @Test
    @DisplayName("isIngestMode is false when disabled, even with a well-formed ARN")
    void isIngestMode_disabled_isFalse() {
        final KvsStreamPoolService service = KvsStreamPoolService.forTest(false, VALID_ARN);
        assertThat(service.isIngestMode()).isFalse();
    }

    @Test
    @DisplayName("isIngestMode is true for a well-formed pool ARN")
    void isIngestMode_validArn_isTrue() {
        final KvsStreamPoolService service = KvsStreamPoolService.forTest(true, VALID_ARN);
        assertThat(service.isIngestMode()).isTrue();
    }

    @Test
    @DisplayName("getStreamPoolRegion resolves from a well-formed ARN")
    void getStreamPoolRegion_validArn_returnsRegion() {
        final KvsStreamPoolService service = KvsStreamPoolService.forTest(true, VALID_ARN);
        assertThat(service.getStreamPoolRegion()).isEqualTo("us-east-1");
    }

    @Test
    @DisplayName("getStreamPoolRegion is blank for the placeholder ARN")
    void getStreamPoolRegion_placeholderArn_isBlank() {
        final KvsStreamPoolService service = KvsStreamPoolService.forTest(true, PLACEHOLDER_ARN);
        assertThat(service.getStreamPoolRegion()).isBlank();
    }
}
