package com.careconnect.service.conditiondetection;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import java.nio.file.Path;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/**
 * HTTP client for the DAM inference sidecar, which runs in the same ECS task and is reached on
 * localhost. See {@code backend/condition-detection-sidecar/README.md} for the contract.
 */
@Component
@ConditionalOnProperty(
        name = "careconnect.condition-detection.dam.enabled",
        havingValue = "true",
        matchIfMissing = true)
public class DamSidecarClient {

    /** Sidecar status when the model produced scores. */
    public static final String STATUS_OK = "OK";

    /** Sidecar status when VAD found less speech than the model's minimum. */
    public static final String STATUS_INSUFFICIENT_SPEECH = "INSUFFICIENT_SPEECH";

    /** Client-side status for audio the sidecar rejected as unreadable (HTTP 400). */
    public static final String STATUS_INVALID_AUDIO = "INVALID_AUDIO";

    private final RestTemplate http;
    private final String baseUrl;

    public DamSidecarClient(
            final RestTemplateBuilder builder,
            @Value("${careconnect.condition-detection.dam.url:http://localhost:8000}")
            final String baseUrl,
            @Value("${careconnect.condition-detection.dam.read-timeout-seconds:1200}")
            final long readTimeoutSeconds) {
        this.http = builder
                .connectTimeout(Duration.ofSeconds(5))
                .readTimeout(Duration.ofSeconds(readTimeoutSeconds))
                .build();
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
    }

    /**
     * Whether the sidecar is up and has finished loading the model. Any error (connection
     * refused while the container restarts, 503 while loading) means "not yet".
     */
    public boolean isReady() {
        try {
            return http.getForEntity(baseUrl + "/health", String.class).getStatusCode().is2xxSuccessful();
        } catch (RestClientException notReady) {
            return false;
        }
    }

    /**
     * Sends one mono WAV for analysis. A 400 from the sidecar is returned as
     * {@link #STATUS_INVALID_AUDIO}; any other failure (sidecar down, still loading, 5xx) is
     * thrown so the run retries.
     */
    public DamResult analyze(final Path wav) {
        final MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        body.add("audio", new FileSystemResource(wav));
        final HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.MULTIPART_FORM_DATA);
        try {
            final DamResult result = http.postForObject(
                    baseUrl + "/v1/analyze", new HttpEntity<>(body, headers), DamResult.class);
            if (result == null || result.status() == null) {
                throw new IllegalStateException("DAM sidecar returned an empty response");
            }
            return result;
        } catch (HttpClientErrorException clientError) {
            if (clientError.getStatusCode().isSameCodeAs(HttpStatus.BAD_REQUEST)) {
                return new DamResult(STATUS_INVALID_AUDIO, null, null, null, null);
            }
            throw clientError;
        }
    }

    /** Sidecar response body. Unknown fields are ignored so the sidecar can add more. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record DamResult(
            String status,
            @JsonProperty("speech_seconds") Double speechSeconds,
            @JsonProperty("model_revision") String modelRevision,
            DamScore depression,
            DamScore anxiety) {
    }

    /** One condition's raw score and published-threshold level. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record DamScore(Double raw, Integer level) {
    }
}
