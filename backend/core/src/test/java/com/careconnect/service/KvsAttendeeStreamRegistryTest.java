package com.careconnect.service;

import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("KvsAttendeeStreamRegistry Tests")
class KvsAttendeeStreamRegistryTest {

    private static final String CALL_ID = "call-1";
    private static final String ORPHAN_ID = "orphan-attendee";
    private static final String ROSTER_ID = "roster-attendee";
    private static final String STREAM_ARN = "arn:aws:kinesisvideo:us-east-1:1:stream/x";

    private KvsAttendeeStreamRegistry registry;

    @BeforeEach
    void setUp() {
        registry = new KvsAttendeeStreamRegistry();
    }

    @Test
    @DisplayName("tryAliasOrphansToRoster maps single orphan to single roster gap")
    void tryAliasOrphansToRoster_singleOrphan() {
        registry.register(CALL_ID, ORPHAN_ID, STREAM_ARN);

        final boolean aliased = registry.tryAliasOrphansToRoster(CALL_ID, List.of(ROSTER_ID));

        assertThat(aliased).isTrue();
        assertThat(registry.getStreamArn(CALL_ID, ROSTER_ID)).isEqualTo(STREAM_ARN);
        assertThat(registry.getStreamArn(CALL_ID, ORPHAN_ID)).isEqualTo(STREAM_ARN);
    }

    @Test
    @DisplayName("tryAliasOrphansToRoster no-op when multiple orphans")
    void tryAliasOrphansToRoster_multipleOrphans_noOp() {
        registry.register(CALL_ID, "orphan-1", STREAM_ARN);
        registry.register(CALL_ID, "orphan-2", STREAM_ARN + "/2");

        final boolean aliased =
                registry.tryAliasOrphansToRoster(CALL_ID, List.of(ROSTER_ID, "roster-2"));

        assertThat(aliased).isFalse();
        assertThat(registry.getStreamArn(CALL_ID, ROSTER_ID)).isNull();
    }
}
