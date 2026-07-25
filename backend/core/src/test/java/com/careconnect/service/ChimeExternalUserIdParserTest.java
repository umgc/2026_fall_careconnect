package com.careconnect.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("ChimeExternalUserIdParser")
class ChimeExternalUserIdParserTest {

    @Test
    @DisplayName("legacy ROLE_…_userId still parses")
    void parseUserId_legacyFormat() {
        assertThat(ChimeExternalUserIdParser.parseUserId("CAREGIVER_Test_2")).isEqualTo(2L);
        assertThat(ChimeExternalUserIdParser.parseRole("CAREGIVER_Test_2")).isEqualTo("CAREGIVER");
    }

    @Test
    @DisplayName("opaque UUID is not parsed as ROLE_userId")
    void parseUserId_opaqueUuid_returnsNull() {
        final String opaque = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
        assertThat(ChimeExternalUserIdParser.isOpaqueExternalUserId(opaque)).isTrue();
        assertThat(ChimeExternalUserIdParser.parseUserId(opaque)).isNull();
        assertThat(ChimeExternalUserIdParser.parseRole(opaque)).isEqualTo("UNKNOWN");
    }

    @Test
    @DisplayName("pipeline-internal ids are detected")
    void isPipelineInternal() {
        assertThat(ChimeExternalUserIdParser.isPipelineInternal("aws:MediaPipeline-abc")).isTrue();
        assertThat(ChimeExternalUserIdParser.isPipelineInternal("CAREGIVER_1")).isFalse();
    }
}
