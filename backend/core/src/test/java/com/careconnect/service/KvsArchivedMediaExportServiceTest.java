package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoClient;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointRequest;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.KinesisVideoArchivedMediaClient;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.Fragment;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.GetMediaForFragmentListResponse;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsRequest;
import software.amazon.awssdk.services.kinesisvideoarchivedmedia.model.ListFragmentsResponse;

/**
 * Validates the KVS export and where the requested attendee window lies inside the exported file.
 * Fragments are fetched with ten seconds of padding, so the file usually starts before the window;
 * the trim offsets are what keep that padding (possibly another call's audio on a reused pool
 * stream) out of the transcoded WAV.
 *
 * <p>The KVS control-plane and archived-media clients are mocked (network boundaries). The service
 * builds its archived-media client per endpoint, so a spy replaces that one factory method.</p>
 */
class KvsArchivedMediaExportServiceTest {

    private static final String ARN = "arn:aws:kinesisvideo:us-east-1:123:stream/ChimeMediaPipelines-x/1";
    private static final Instant WINDOW_START = Instant.parse("2026-10-24T15:00:00Z");
    private static final Instant WINDOW_END = Instant.parse("2026-10-24T15:05:00Z");

    private KinesisVideoClient kinesisVideoClient;
    private KinesisVideoArchivedMediaClient archivedClient;
    private KvsArchivedMediaExportService service;

    @BeforeEach
    void setUp() {
        kinesisVideoClient = mock(KinesisVideoClient.class);
        archivedClient = mock(KinesisVideoArchivedMediaClient.class);
        when(kinesisVideoClient.getDataEndpoint(any(GetDataEndpointRequest.class)))
                .thenReturn(GetDataEndpointResponse.builder().dataEndpoint("https://kvs.example").build());
        final KvsArchivedMediaExportService real = new KvsArchivedMediaExportService();
        ReflectionTestUtils.setField(real, "kinesisVideoClient", kinesisVideoClient);
        service = spy(real);
        doReturn(archivedClient).when(service).archivedClient(any(Region.class), any(String.class));
    }

    private static Fragment fragment(final String number, final Instant serverTimestamp) {
        return Fragment.builder().fragmentNumber(number).serverTimestamp(serverTimestamp).build();
    }

    private void listReturns(final Fragment... fragments) {
        when(archivedClient.listFragments(any(ListFragmentsRequest.class)))
                .thenReturn(ListFragmentsResponse.builder().fragments(fragments).build());
    }

    // ------------------------------------------------------- exportAttendeeRange

    /**
     * Scenario: KVS returns fragments out of order, plus one without a timestamp and one without
     * a number. The invalid ones are dropped, the rest are fetched in time order, the media is
     * written to a temp file, and the trim starts at the window, 8 s into the earliest fragment.
     */
    @Test
    void export_writesSortedValidFragmentsAndTrimsFromEarliest() throws Exception {
        // Arrange: earliest valid fragment began 8 s before the join (inside the padding).
        listReturns(
                fragment("f2", WINDOW_START.plusSeconds(2)),
                fragment("no-time", null),
                fragment("f1", WINDOW_START.minusSeconds(8)),
                fragment(" ", WINDOW_START));
        final byte[] media = "mkv-bytes".getBytes(StandardCharsets.UTF_8);
        when(archivedClient.getMediaForFragmentList(any(GetMediaForFragmentListRequest.class)))
                .thenReturn(new ResponseInputStream<>(
                        GetMediaForFragmentListResponse.builder().build(),
                        AbortableInputStream.create(new ByteArrayInputStream(media))));

        // Act
        final KvsAudioClip clip = service.exportAttendeeRange(ARN, WINDOW_START, WINDOW_END);

        // Assert
        try {
            final ArgumentCaptor<GetMediaForFragmentListRequest> request =
                    ArgumentCaptor.forClass(GetMediaForFragmentListRequest.class);
            verify(archivedClient).getMediaForFragmentList(request.capture());
            assertThat(request.getValue().fragments()).containsExactly("f1", "f2");
            assertThat(clip.trimStartMs()).isEqualTo(8_000L);
            assertThat(clip.trimEndMs()).isEqualTo(308_000L);
            assertThat(Files.readAllBytes(clip.file())).isEqualTo(media);
        } finally {
            Files.deleteIfExists(clip.file());
        }
    }

    /** Scenario: the stream has nothing in the padded window — not even padding. */
    @Test
    void export_noFragments_throwsWithoutFetchingMedia() {
        listReturns();

        assertThatThrownBy(() -> service.exportAttendeeRange(ARN, WINDOW_START, WINDOW_END))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("No KVS fragments found");
        verify(archivedClient, never()).getMediaForFragmentList(any(GetMediaForFragmentListRequest.class));
    }

    /** Scenario: only trailing padding exists (the stream started after the leave): nothing to decode. */
    @Test
    void export_onlyFragmentsAfterWindow_throwsWithoutFetchingMedia() {
        listReturns(fragment("late", WINDOW_END.plusSeconds(3)));

        assertThatThrownBy(() -> service.exportAttendeeRange(ARN, WINDOW_START, WINDOW_END))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("inside window");
        verify(archivedClient, never()).getMediaForFragmentList(any(GetMediaForFragmentListRequest.class));
    }

    /** Scenario: an inverted window is a caller bug, rejected before any KVS call. */
    @Test
    void export_invalidWindow_throwsBeforeCallingKvs() {
        assertThatThrownBy(() -> service.exportAttendeeRange(ARN, WINDOW_END, WINDOW_START))
                .isInstanceOf(IllegalArgumentException.class);
        verify(archivedClient, never()).listFragments(any(ListFragmentsRequest.class));
    }

    // ------------------------------------------------------------- trimWindowMs

    /** Scenario: the first fetched fragment began 8 s before the join (inside the padding). */
    @Test
    void trimWindowMs_fileStartsInPadding_skipsThePadding() {
        // Arrange: 8 s of someone else's (or nobody's) audio precedes the window.
        final Instant mediaStart = WINDOW_START.minusSeconds(8);

        // Act
        final long[] trim = KvsArchivedMediaExportService.trimWindowMs(mediaStart, WINDOW_START, WINDOW_END);

        // Assert: start 8 s in; end 8 s + 5 min in, so the trailing padding is cut too.
        assertThat(trim).containsExactly(8_000L, 308_000L);
    }

    /** Scenario: the stream's first audio is 3 s after the join, so nothing precedes the window. */
    @Test
    void trimWindowMs_fileStartsInsideWindow_startsAtZero() {
        final long[] trim = KvsArchivedMediaExportService.trimWindowMs(
                WINDOW_START.plusSeconds(3), WINDOW_START, WINDOW_END);

        assertThat(trim).containsExactly(0L, 297_000L);
    }

    /** Scenario: only trailing padding was found (first fragment after the leave): nothing to decode. */
    @Test
    void trimWindowMs_fileStartsAfterWindow_isEmpty() {
        assertThat(KvsArchivedMediaExportService.trimWindowMs(
                WINDOW_END.plusSeconds(2), WINDOW_START, WINDOW_END)).isEmpty();
    }
}
