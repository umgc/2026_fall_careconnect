package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallRecording;
import com.careconnect.model.PostCallTranscriptionJob;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.PostCallTranscriptionJobRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class PostCallTranscriptionDurabilityTest {
    @Mock
    private CallTranscriptService callTranscriptService;
    @Mock
    private CallTelemetryService callTelemetryService;
    @Mock
    private CallRecordingRepository recordingRepository;
    @Mock
    private PostCallTranscriptionJobRepository jobRepository;
    @InjectMocks
    private PostCallTranscriptionService service;

    @Test
    void enqueue_persistsExactKeysBeforeWorkerSubmission() {
        final CallRecording recording = new CallRecording();
        recording.setId(12L);
        recording.setCallId("call/12");
        recording.setGeneration(3L);
        recording.setS3Bucket("recording-bucket");
        when(jobRepository.findByRecordingId(12L)).thenReturn(Optional.empty());
        when(jobRepository.save(any(PostCallTranscriptionJob.class))).thenAnswer(invocation -> {
            final PostCallTranscriptionJob job = invocation.getArgument(0);
            job.setId(55L);
            return job;
        });

        service.transcribeAndCleanup(
                "call/12", recording, "recordings/call-12/final.mp4");

        final ArgumentCaptor<PostCallTranscriptionJob> captor =
                ArgumentCaptor.forClass(PostCallTranscriptionJob.class);
        verify(jobRepository).save(captor.capture());
        assertThat(captor.getValue().getState()).isEqualTo("READY");
        assertThat(captor.getValue().getMediaKey())
                .isEqualTo("recordings/call-12/final.mp4");
        assertThat(captor.getValue().getOutputKey())
                .isEqualTo("transcription-jobs/call-12/12/cc-call-12-12.json");
        verify(jobRepository).markDueNow(55L);
        verify(recordingRepository).save(any(CallRecording.class));
        assertThat(recording.getTranscriptionStatus()).isEqualTo("READY");
    }
}
