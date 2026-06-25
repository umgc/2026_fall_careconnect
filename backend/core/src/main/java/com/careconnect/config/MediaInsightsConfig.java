package com.careconnect.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Resolved Media Insights pipeline configuration ARN for per-attendee KVS capture. */
@Component
public class MediaInsightsConfig {

    private final String mediaInsightsConfigArn;

    public MediaInsightsConfig(
            @Value("${careconnect.chime.media-insights-config-arn:}") final String mediaInsightsConfigArn) {
        this.mediaInsightsConfigArn =
                mediaInsightsConfigArn == null ? "" : mediaInsightsConfigArn.trim();
    }

    /** Visible for unit tests without Spring context. */
    static MediaInsightsConfig forTest(final String mediaInsightsConfigArn) {
        return new MediaInsightsConfig(mediaInsightsConfigArn);
    }

    public boolean isConfigured() {
        return !mediaInsightsConfigArn.isBlank();
    }

    public String getMediaInsightsConfigArn() {
        return mediaInsightsConfigArn;
    }

    /**
     * Returns the configuration ARN or throws when speaker capture cannot start.
     *
     * @return non-blank Media Insights configuration ARN
     */
    public String requireMediaInsightsConfigArn() {
        if (!isConfigured()) {
            throw new IllegalStateException(
                    "Media Insights configuration ARN is not set"
                            + " (careconnect.chime.media-insights-config-arn)");
        }
        return mediaInsightsConfigArn;
    }
}
