package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("KvsFragmentMetadataReader Tests")
class KvsFragmentMetadataReaderTest {

    private static final String MEETING_ID = "1e6bf4f5-f4b5-4917-b8c9-bda45c340706";
    private static final String ATTENDEE_ID = "a0b1c2d3-e4f5-6789-abcd-ef0123456789";

    @Test
    @DisplayName("SPEAKER-046: matches attendee when meeting and attendee ids appear in MKV bytes")
    void matchAttendeeId_found() {
        final byte[] payload =
                ("prefix-meetingId-" + MEETING_ID + "-attendeeId-" + ATTENDEE_ID + "-suffix")
                        .getBytes(StandardCharsets.UTF_8);

        assertThat(
                        KvsFragmentMetadataReader.matchAttendeeId(
                                payload, MEETING_ID, Set.of(ATTENDEE_ID, "other-id")))
                .contains(ATTENDEE_ID);
    }

    @Test
    @DisplayName("SPEAKER-047: rejects fragment when meeting id missing")
    void matchAttendeeId_wrongMeeting() {
        final byte[] payload =
                ("attendeeId-" + ATTENDEE_ID).getBytes(StandardCharsets.UTF_8);

        assertThat(
                        KvsFragmentMetadataReader.matchAttendeeId(
                                payload, MEETING_ID, Set.of(ATTENDEE_ID)))
                .isEmpty();
    }

    @Test
    @DisplayName("SPEAKER-048: matches meeting id without hyphens in MKV bytes")
    void containsMeetingId_compactUuid() {
        final String compact = MEETING_ID.replace("-", "");
        final byte[] payload =
                ("meetingId-" + compact + "-attendee-" + ATTENDEE_ID).getBytes(StandardCharsets.UTF_8);

        assertThat(KvsFragmentMetadataReader.containsMeetingId(payload, MEETING_ID)).isTrue();
        assertThat(
                        KvsFragmentMetadataReader.matchAttendeeId(
                                payload, MEETING_ID, Set.of(ATTENDEE_ID)))
                .contains(ATTENDEE_ID);
    }
}
