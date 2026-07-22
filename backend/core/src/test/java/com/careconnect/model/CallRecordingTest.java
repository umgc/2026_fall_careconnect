package com.careconnect.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("CallRecording entity Tests")
class CallRecordingTest {

    @Test
    @DisplayName("SPEAKER-010: kvsPipelineId field maps on CallRecording entity")
    void kvsPipelineId_roundTrips() {
        final CallRecording recording = new CallRecording();
        recording.setKvsPipelineId("kvs-pipeline-xyz");

        assertThat(recording.getKvsPipelineId()).isEqualTo("kvs-pipeline-xyz");
    }
}
