package com.careconnect.config;

import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.SdkClient;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Builds the remaining AWS SDK client beans. Building a client is local-only (no network call
 * is made until an operation is invoked), so this stays hermetic.
 */
class AwsAccessConfigClientsCoverageTest {

    @Test
    void buildsServiceClientBeans() {
        AwsAccessConfig config = new AwsAccessConfig();
        ReflectionTestUtils.setField(config, "awsRegion", "us-east-1");
        List<SdkClient> clients = List.of(
                config.chimeSdkMeetingsClient(),
                config.bedrockRuntimeClient(),
                config.chimeSdkMediaPipelinesClient(),
                config.kinesisVideoClient(),
                config.stsClient(),
                config.iamClient(),
                config.transcribeClient());
        try (S3Presigner presigner = config.s3Presigner()) {
            assertThat(presigner).isNotNull();
        }
        for (SdkClient client : clients) {
            assertThat(client.serviceName()).isNotBlank();
            client.close();
        }
    }
}
