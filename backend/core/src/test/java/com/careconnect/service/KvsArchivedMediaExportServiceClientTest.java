package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.RETURNS_SELF;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.time.Instant;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.slf4j.LoggerFactory;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoClient;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoServiceClientConfiguration;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointRequest;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.KinesisVideoArchivedMediaClient;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.KinesisVideoArchivedMediaClientBuilder;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.Fragment;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsResponse;

/**
 * Covers input guards, the default region and the real archived-media client factory of {@link
 * KvsArchivedMediaExportService}; the client builder is statically mocked so nothing is contacted.
 */
@DisplayName("KvsArchivedMediaExportService guards and client factory")
class KvsArchivedMediaExportServiceClientTest {

    private static final Instant START = Instant.parse("2026-10-01T10:00:00Z");
    private static final Instant END = Instant.parse("2026-10-01T10:05:00Z");

    private final Logger serviceLogger = (Logger) LoggerFactory.getLogger(KvsArchivedMediaExportService.class);
    private Level originalLevel;
    private KvsArchivedMediaExportService service;
    private KinesisVideoClient kinesisVideoClient;

    @BeforeEach
    void setUp() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.INFO);
        kinesisVideoClient = mock(KinesisVideoClient.class);
        when(kinesisVideoClient.getDataEndpoint(any(GetDataEndpointRequest.class)))
                .thenReturn(GetDataEndpointResponse.builder().dataEndpoint("https://b-test.example").build());
        when(kinesisVideoClient.serviceClientConfiguration())
                .thenReturn(mock(KinesisVideoServiceClientConfiguration.class));
        service = new KvsArchivedMediaExportService();
        ReflectionTestUtils.setField(service, "kinesisVideoClient", kinesisVideoClient);
    }

    @AfterEach
    void restore() {
        serviceLogger.setLevel(originalLevel);
    }

    @Test
    @DisplayName("rejects a blank ARN and an inverted window")
    void guards() {
        assertThatThrownBy(() -> service.exportAttendeeRange(" ", START, END))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.exportAttendeeRange("arn:x", END, START))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("exports through the built client, defaulting the region for a short ARN")
    void exportsThroughBuiltClient() throws Exception {
        final KinesisVideoArchivedMediaClient client = mock(KinesisVideoArchivedMediaClient.class);
        final KinesisVideoArchivedMediaClientBuilder builder =
                mock(KinesisVideoArchivedMediaClientBuilder.class, RETURNS_SELF);
        when(builder.build()).thenReturn(client);
        when(client.listFragments(any(ListFragmentsRequest.class)))
                .thenReturn(ListFragmentsResponse.builder()
                        .fragments(Fragment.builder().fragmentNumber("1").serverTimestamp(START).build())
                        .build());
        when(client.getMediaForFragmentList(any(GetMediaForFragmentListRequest.class)))
                .thenReturn(new ResponseInputStream<>(GetMediaForFragmentListResponse.builder().build(),
                        AbortableInputStream.create(new ByteArrayInputStream(new byte[] {1, 2}))));

        try (MockedStatic<KinesisVideoArchivedMediaClient> statics = mockStatic(KinesisVideoArchivedMediaClient.class)) {
            statics.when(KinesisVideoArchivedMediaClient::builder).thenReturn(builder);
            final KvsAudioClip clip = service.exportAttendeeRange("arn:aws:kv", START, END);
            try {
                assertThat(Files.readAllBytes(clip.file())).containsExactly(1, 2);
            } finally {
                Files.deleteIfExists(clip.file());
            }
        }
    }
}
