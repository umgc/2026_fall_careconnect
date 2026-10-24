package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestTemplate;

/**
 * Unit tests for {@link DamSidecarClient}. The sidecar is replaced by a
 * {@link MockRestServiceServer} bound to the client's own RestTemplate, so the real request
 * building and response mapping are exercised without a network.
 */
class DamSidecarClientTest {

    private static final String URL = "http://sidecar.test:8000/v1/analyze";
    private static final String HEALTH_URL = "http://sidecar.test:8000/health";

    private DamSidecarClient client;
    private MockRestServiceServer server;
    private Path wav;

    @BeforeEach
    void setUp() throws Exception {
        client = new DamSidecarClient(new RestTemplateBuilder(), "http://sidecar.test:8000", 30L);
        server = MockRestServiceServer.bindTo(
                (RestTemplate) ReflectionTestUtils.getField(client, "http")).build();
        wav = Files.createTempFile("dam-client", ".wav");
        Files.write(wav, new byte[] {'R', 'I', 'F', 'F', 0, 0, 0, 0});
    }

    @AfterEach
    void tearDown() throws Exception {
        Files.deleteIfExists(wav);
    }

    /** Scenario: a realistic OK body with snake_case fields plus unknown top-level and nested fields the sidecar may add later. */
    @Test
    void analyze_okResponse_mapsSnakeCaseFieldsAndIgnoresUnknownFields() {
        server.expect(requestTo(URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(content().contentTypeCompatibleWith(MediaType.MULTIPART_FORM_DATA))
                .andRespond(withSuccess("""
                        {"status":"OK","speech_seconds":42.5,"model_revision":"dam-3.1",
                         "depression":{"raw":0.31,"level":1,"extra_inner":true},
                         "anxiety":{"raw":0.77,"level":3},
                         "brand_new_field":{"x":1}}
                        """, MediaType.APPLICATION_JSON));

        final DamSidecarClient.DamResult result = client.analyze(wav);

        assertThat(result.status()).isEqualTo(DamSidecarClient.STATUS_OK);
        assertThat(result.speechSeconds()).isEqualTo(42.5);
        assertThat(result.modelRevision()).isEqualTo("dam-3.1");
        assertThat(result.depression()).isEqualTo(new DamSidecarClient.DamScore(0.31, 1));
        assertThat(result.anxiety()).isEqualTo(new DamSidecarClient.DamScore(0.77, 3));
        server.verify();
    }

    /** Scenario: the multipart request carries a part named audio with the file bytes. */
    @Test
    void analyze_sendsAudioPartWithFileContent() {
        server.expect(requestTo(URL))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("name=\"audio\"")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("RIFF")))
                .andRespond(withSuccess("{\"status\":\"OK\"}", MediaType.APPLICATION_JSON));

        assertThat(client.analyze(wav).status()).isEqualTo("OK");
        server.verify();
    }

    /** Scenario: a 200 with INSUFFICIENT_SPEECH is a normal result, not an error. */
    @Test
    void analyze_insufficientSpeech_isReturnedWithSpeechSeconds() {
        server.expect(requestTo(URL))
                .andRespond(withSuccess(
                        "{\"status\":\"INSUFFICIENT_SPEECH\",\"speech_seconds\":3.25}",
                        MediaType.APPLICATION_JSON));

        final DamSidecarClient.DamResult result = client.analyze(wav);

        assertThat(result.status()).isEqualTo(DamSidecarClient.STATUS_INSUFFICIENT_SPEECH);
        assertThat(result.speechSeconds()).isEqualTo(3.25);
        assertThat(result.depression()).isNull();
        assertThat(result.anxiety()).isNull();
    }

    /** Scenario: HTTP 400 means unreadable audio, mapped client-side to INVALID_AUDIO. */
    @Test
    void analyze_badRequest_isReportedAsInvalidAudio() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.BAD_REQUEST));

        final DamSidecarClient.DamResult result = client.analyze(wav);

        assertThat(result.status()).isEqualTo(DamSidecarClient.STATUS_INVALID_AUDIO);
        assertThat(result.depression()).isNull();
        assertThat(result.speechSeconds()).isNull();
    }

    /** Scenario: /health answers 200 once the model is loaded, so the sidecar is ready. */
    @Test
    void isReady_healthOk_isTrue() {
        server.expect(requestTo(HEALTH_URL))
                .andRespond(withSuccess("{\"status\":\"ok\"}", MediaType.APPLICATION_JSON));

        assertThat(client.isReady()).isTrue();
    }

    /** Scenario: /health answers 503 while the model is still loading, so the run should wait. */
    @Test
    void isReady_stillLoading_isFalse() {
        server.expect(requestTo(HEALTH_URL)).andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));

        assertThat(client.isReady()).isFalse();
    }

    /** Scenario: nothing is listening (container restarting), which must read as "not ready", not throw. */
    @Test
    void isReady_connectionRefused_isFalse() {
        server.expect(requestTo(HEALTH_URL)).andRespond(request -> {
            throw new java.net.ConnectException("Connection refused");
        });

        assertThat(client.isReady()).isFalse();
    }

    /** Scenario: 503 (model still loading) must throw so the run retries. */
    @Test
    void analyze_serviceUnavailable_throwsSoTheRunRetries() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));

        assertThatThrownBy(() -> client.analyze(wav)).isInstanceOf(HttpServerErrorException.class);
    }

    /** Scenario: a non-400 4xx (422) is not audio-specific and is rethrown. */
    @Test
    void analyze_otherClientError_isRethrown() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.UNPROCESSABLE_ENTITY));

        assertThatThrownBy(() -> client.analyze(wav))
                .isInstanceOf(org.springframework.web.client.HttpClientErrorException.class);
    }

    /** Scenario: a 200 with no body is treated as a failure. */
    @Test
    void analyze_emptyBody_throwsIllegalState() {
        server.expect(requestTo(URL)).andRespond(withSuccess());

        assertThatThrownBy(() -> client.analyze(wav)).isInstanceOf(IllegalStateException.class);
    }

    /** Scenario: a JSON body missing status is unusable. */
    @Test
    void analyze_responseWithoutStatus_throwsIllegalState() {
        server.expect(requestTo(URL))
                .andRespond(withSuccess("{\"speech_seconds\":1.0}", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> client.analyze(wav))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("empty response");
    }

    /** Scenario: a configured URL ending in / is normalized. */
    @Test
    void analyze_trailingSlashInBaseUrl_doesNotProduceDoubleSlash() {
        final DamSidecarClient slashClient =
                new DamSidecarClient(new RestTemplateBuilder(), "http://sidecar.test:8000/", 30L);
        final MockRestServiceServer slashServer = MockRestServiceServer.bindTo(
                (RestTemplate) ReflectionTestUtils.getField(slashClient, "http")).build();
        slashServer.expect(requestTo(URL))
                .andRespond(withSuccess("{\"status\":\"OK\"}", MediaType.APPLICATION_JSON));

        assertThat(slashClient.analyze(wav).status()).isEqualTo("OK");
        slashServer.verify();
    }
}
