package com.careconnect.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("CallRecording entity Tests")
class CallRecordingTest {

    @Test
    @DisplayName("SPEAKER-010: mediaStreamPipelineId field maps on CallRecording entity")
    void mediaStreamPipelineId_roundTrips() {
        final CallRecording recording = new CallRecording();
        recording.setMediaStreamPipelineId("media-stream-pipeline-xyz");

        assertThat(recording.getMediaStreamPipelineId()).isEqualTo("media-stream-pipeline-xyz");
    }
}
