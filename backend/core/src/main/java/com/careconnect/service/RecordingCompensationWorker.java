package com.careconnect.service;

import com.careconnect.model.RecordingCompensation;
import com.careconnect.repository.RecordingCompensationRepository;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Propagation;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.model.DeleteMediaCapturePipelineRequest;

/** Restart-safe compensation worker for leaked AWS capture resources. */
@Slf4j
@Service
@RequiredArgsConstructor
public class RecordingCompensationWorker {
    private static final long LEASE_SECONDS = 120L;
    private static final long RETRY_SECONDS = 30L;

    private final RecordingCompensationRepository repository;

    @Autowired(required = false)
    private ChimeSdkMediaPipelinesClient pipelinesClient;

    @Scheduled(fixedDelayString = "${careconnect.recording.compensation.interval-ms:15000}")
    public void runDue() {
        for (final Long id : repository.findDueIds(25)) {
            process(id);
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void enqueueCapture(
            final String callId,
            final long generation,
            final String pipelineId,
            final String bucket,
            final String prefix) {
        final RecordingCompensation command = new RecordingCompensation();
        command.setCallId(callId);
        command.setGeneration(generation);
        command.setResourceType("MEDIA_CAPTURE_PIPELINE");
        command.setAwsResourceId(pipelineId);
        command.setS3Bucket(bucket);
        command.setS3Prefix(prefix);
        command.setState("READY");
        command.setNextAttemptAt(LocalDateTime.now(ZoneOffset.UTC));
        repository.save(command);
    }

    @Transactional
    public void process(final Long id) {
        final UUID token = UUID.randomUUID();
        if (repository.claim(id, token, LEASE_SECONDS) != 1) {
            return;
        }
        final RecordingCompensation command =
                repository.findByIdAndClaimToken(id, token).orElse(null);
        if (command == null) {
            return;
        }
        try {
            if (pipelinesClient == null) {
                throw new IllegalStateException("AWS media pipeline client unavailable");
            }
            pipelinesClient.deleteMediaCapturePipeline(
                    DeleteMediaCapturePipelineRequest.builder()
                            .mediaPipelineId(command.getAwsResourceId())
                            .build());
            repository.complete(id, token);
        } catch (Exception exception) {
            if (isNotFound(exception)) {
                repository.complete(id, token);
            } else {
                repository.retry(id, token, RETRY_SECONDS, truncate(exception.getMessage()));
                log.warn("Recording compensation {} remains retryable: {}", id, exception.getMessage());
            }
        }
    }

    private static boolean isNotFound(final Exception exception) {
        return exception instanceof
                software.amazon.awssdk.services.chimesdkmediapipelines.model
                        .ChimeSdkMediaPipelinesException serviceException
                && serviceException.statusCode() == 404;
    }

    private static String truncate(final String value) {
        if (value == null || value.length() <= 2000) {
            return value;
        }
        return value.substring(0, 2000);
    }
}
