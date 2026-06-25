package com.careconnect.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@DisplayName("MediaInsightsConfig Tests")
class MediaInsightsConfigTest {

    private static final String CONFIG_ARN =
            "arn:aws:chime:us-east-1:123456789012:media-insights-pipeline-configuration/abc";

    @Test
    @DisplayName("SPEAKER-030: loads ARN from property value")
    void loadsArnFromProperty() {
        final MediaInsightsConfig config = MediaInsightsConfig.forTest(CONFIG_ARN);

        assertThat(config.isConfigured()).isTrue();
        assertThat(config.getMediaInsightsConfigArn()).isEqualTo(CONFIG_ARN);
        assertThat(config.requireMediaInsightsConfigArn()).isEqualTo(CONFIG_ARN);
    }

    @Test
    @DisplayName("SPEAKER-031: blank ARN is not configured")
    void blankArn_notConfigured() {
        final MediaInsightsConfig config = MediaInsightsConfig.forTest("   ");

        assertThat(config.isConfigured()).isFalse();
        assertThatThrownBy(config::requireMediaInsightsConfigArn)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("careconnect.chime.media-insights-config-arn");
    }
}
