package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallAttendee;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
@DisplayName("KvsAttendeeStreamResolver Tests")
class KvsAttendeeStreamResolverTest {

    private static final String CALL_ID = "call-1";
    private static final String MEETING_ID = "meeting-uuid";
    private static final String MEDIA_PIPELINE_ID = "media-pipeline-1";

    @Mock private KvsPoolStreamDiscoveryService poolStreamDiscoveryService;
    @Mock private KvsStreamPoolService kvsStreamPoolService;

    private KvsAttendeeStreamRegistry registry;
    private KvsAttendeeStreamResolver resolver;

    @BeforeEach
    void setUp() {
        registry = new KvsAttendeeStreamRegistry();
        resolver =
                new KvsAttendeeStreamResolver(registry, poolStreamDiscoveryService, kvsStreamPoolService);
        ReflectionTestUtils.setField(resolver, "discoveryTimeoutMs", 2000L);
    }

    @Test
    @DisplayName("SPEAKER-044: returns registry mappings without KVS polling when complete")
    void resolve_registryComplete_skipsPolling() {
        registry.register(CALL_ID, "att-1", "arn:aws:kinesisvideo:us-east-1:1:stream/a/1");
        registry.register(CALL_ID, "att-2", "arn:aws:kinesisvideo:us-east-1:1:stream/b/1");

        final List<CallAttendee> attendees =
                List.of(buildAttendee("att-1", 1), buildAttendee("att-2", 2));

        final Map<String, String> mappings =
                resolver.resolve(CALL_ID, attendees, MEDIA_PIPELINE_ID, MEETING_ID);

        assertThat(mappings)
                .containsEntry("att-1", "arn:aws:kinesisvideo:us-east-1:1:stream/a/1")
                .containsEntry("att-2", "arn:aws:kinesisvideo:us-east-1:1:stream/b/1");
        verify(poolStreamDiscoveryService, never())
                .discoverAndRegister(eq(CALL_ID), eq(MEETING_ID), eq(List.of("att-1", "att-2")));
    }

    @Test
    @DisplayName("SPEAKER-045: ingest mode polls KVS until mappings appear")
    void resolve_ingestMode_pollsDiscovery() {
        when(kvsStreamPoolService.isIngestMode()).thenReturn(true);

        final CallAttendee attendee = buildAttendee("att-caregiver", 1);
        org.mockito.Mockito.doAnswer(
                        invocation -> {
                            registry.register(
                                    CALL_ID,
                                    "att-caregiver",
                                    "arn:aws:kinesisvideo:us-east-1:1:stream/chime/1");
                            return null;
                        })
                .when(poolStreamDiscoveryService)
                .discoverAndRegister(eq(CALL_ID), eq(MEETING_ID), eq(List.of("att-caregiver")));

        final Map<String, String> mappings =
                resolver.resolve(
                        CALL_ID, List.of(attendee), MEDIA_PIPELINE_ID, MEETING_ID);

        assertThat(mappings)
                .containsEntry(
                        "att-caregiver", "arn:aws:kinesisvideo:us-east-1:1:stream/chime/1");
        verify(poolStreamDiscoveryService)
                .discoverAndRegister(eq(CALL_ID), eq(MEETING_ID), eq(List.of("att-caregiver")));
    }

    private static CallAttendee buildAttendee(final String chimeAttendeeId, final int joinOrderMinutes) {
        final CallAttendee attendee = new CallAttendee();
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId(chimeAttendeeId);
        attendee.setJoinedAt(LocalDateTime.now().minusMinutes(joinOrderMinutes));
        return attendee;
    }
}
