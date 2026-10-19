package com.careconnect.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.RecordingCompensation;
import com.careconnect.repository.RecordingCompensationRepository;

import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.DeleteMediaCapturePipelineRequest;

@ExtendWith(MockitoExtension.class)
class RecordingCompensationWorkerTest {
    @Mock
    private RecordingCompensationRepository repository;
    @Mock
    private ChimeSdkMediaPipelinesClient pipelinesClient;
    @InjectMocks
    private RecordingCompensationWorker worker;

    @Test
    void process_claimsAndCompletesLeakedCaptureCleanup() {
        ReflectionTestUtils.setField(worker, "pipelinesClient", pipelinesClient);
        final RecordingCompensation command = new RecordingCompensation();
        command.setId(7L);
        command.setAwsResourceId("pipeline-7");
        when(repository.claim(eq(7L), any(UUID.class), eq(120L))).thenReturn(1);
        when(repository.findByIdAndClaimToken(eq(7L), any(UUID.class)))
                .thenReturn(Optional.of(command));

        worker.process(7L);

        verify(pipelinesClient).deleteMediaCapturePipeline(
                any(DeleteMediaCapturePipelineRequest.class));
        verify(repository).complete(eq(7L), any(UUID.class));
    }
}
