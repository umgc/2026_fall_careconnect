package com.careconnect.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoClient;
import software.amazon.awssdk.services.kinesisvideo.model.APIName;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointRequest;
import software.amazon.awssdk.services.kinesisvideo.model.GetDataEndpointResponse;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Validates which Kinesis Video data endpoint the pool discovery service asks for.
 *
 * <p>Kinesis Video serves each API from its own host, so a data endpoint is only valid for the
 * {@code APIName} it was requested with. {@code GET_MEDIA} resolves to an {@code s-*} host while
 * {@code GET_MEDIA_FOR_FRAGMENT_LIST} and {@code LIST_FRAGMENTS} resolve to a {@code b-*}
 * archived-media host. Reading archived fragments against the {@code GET_MEDIA} endpoint fails,
 * and {@code readRecentFragmentBytesList} swallows that failure as "no fragments" — so
 * attendee→stream discovery silently matched nothing and post-call transcripts fell back to
 * generic {@code Speaker N} labels instead of {@code Caregiver}/{@code Patient}.
 *
 * <p>{@link KinesisVideoClient} is mocked: these tests assert the shape of the outbound request
 * only and must not reach AWS.
 */
@DisplayName("KvsPoolStreamDiscoveryService Tests")
class KvsPoolStreamDiscoveryServiceTest {

    private static final String STREAM_NAME =
            "ChimeMediaPipelines-careconnect-dev-speaker-0bb2fb38-31cd-4493-bc8f-2085abf41c37";

    /** Stand-in for the archived-media host; the value is never dereferenced by these tests. */
    private static final String ENDPOINT = "https://b-e566b37e.kinesisvideo.us-east-1.amazonaws.com";

    private KinesisVideoClient kinesisVideoClient;
    private KvsPoolStreamDiscoveryService service;

    @BeforeEach
    void setUp() {
        kinesisVideoClient = mock(KinesisVideoClient.class);
        when(kinesisVideoClient.getDataEndpoint(any(GetDataEndpointRequest.class)))
                .thenReturn(GetDataEndpointResponse.builder().dataEndpoint(ENDPOINT).build());

        // The registry and pool service are unused on the endpoint-resolution path.
        service =
                new KvsPoolStreamDiscoveryService(
                        mock(KvsAttendeeStreamRegistry.class), mock(KvsStreamPoolService.class));
        // kinesisVideoClient is @Autowired(required = false) field injection, so there is no
        // constructor seam to pass the mock through.
        ReflectionTestUtils.setField(service, "kinesisVideoClient", kinesisVideoClient);
    }

    @Test
    @DisplayName("fragment media endpoint is requested for GET_MEDIA_FOR_FRAGMENT_LIST, not GET_MEDIA")
    void fragmentMediaEndpoint_requestsArchivedMediaApi() {
        // Act
        final String endpoint = service.fragmentMediaEndpoint(STREAM_NAME);

        // Assert — the regression guard: GET_MEDIA here breaks discovery silently.
        final ArgumentCaptor<GetDataEndpointRequest> captor =
                ArgumentCaptor.forClass(GetDataEndpointRequest.class);
        verify(kinesisVideoClient).getDataEndpoint(captor.capture());

        assertThat(captor.getValue().apiName()).isEqualTo(APIName.GET_MEDIA_FOR_FRAGMENT_LIST);
        assertThat(captor.getValue().apiName()).isNotEqualTo(APIName.GET_MEDIA);
        assertThat(captor.getValue().streamName()).isEqualTo(STREAM_NAME);
        assertThat(endpoint).isEqualTo(ENDPOINT);
    }

    @Test
    @DisplayName("list fragments endpoint is requested for LIST_FRAGMENTS")
    void listFragmentsEndpoint_requestsListFragmentsApi() {
        // Act
        final String endpoint = service.listFragmentsEndpoint(STREAM_NAME);

        // Assert
        final ArgumentCaptor<GetDataEndpointRequest> captor =
                ArgumentCaptor.forClass(GetDataEndpointRequest.class);
        verify(kinesisVideoClient).getDataEndpoint(captor.capture());

        assertThat(captor.getValue().apiName()).isEqualTo(APIName.LIST_FRAGMENTS);
        assertThat(captor.getValue().streamName()).isEqualTo(STREAM_NAME);
        assertThat(endpoint).isEqualTo(ENDPOINT);
    }

    @Test
    @DisplayName("listing and fragment-media endpoints are resolved for different APIs")
    void endpoints_areResolvedPerApiName() {
        // Arrange / Act — both lookups happen on every fragment read, one per API.
        service.listFragmentsEndpoint(STREAM_NAME);
        service.fragmentMediaEndpoint(STREAM_NAME);

        // Assert — each call must carry its own APIName rather than reusing one endpoint.
        final ArgumentCaptor<GetDataEndpointRequest> captor =
                ArgumentCaptor.forClass(GetDataEndpointRequest.class);
        verify(kinesisVideoClient, times(2)).getDataEndpoint(captor.capture());

        assertThat(captor.getAllValues())
                .extracting(GetDataEndpointRequest::apiName)
                .containsExactly(APIName.LIST_FRAGMENTS, APIName.GET_MEDIA_FOR_FRAGMENT_LIST)
                .doesNotContain(APIName.GET_MEDIA);
    }
}
