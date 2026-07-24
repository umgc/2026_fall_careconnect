package com.careconnect.service;

import com.careconnect.repository.TranscriptArchiveLifecycleRepository;
import com.careconnect.repository.TranscriptArchiveLifecycleRepository.DeletionClaim;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.services.s3.model.S3Exception;

/** Idempotently removes transcript archive objects requested by committed database changes. */
@Slf4j
@Service
public class TranscriptArchiveDeletionWorker {

  private static final int BATCH_SIZE = 25;
  private static final Duration CLAIM_LEASE = Duration.ofMinutes(5);
  private static final Duration BASE_RETRY_DELAY = Duration.ofMinutes(1);
  private static final Duration MAX_RETRY_DELAY = Duration.ofHours(6);

  private final TranscriptArchiveLifecycleRepository lifecycleRepository;

  @Value("${app.call.transcript.archive.deletion-max-attempts:8}")
  private int maxAttempts = 8;

  @Autowired(required = false)
  private S3StorageService s3StorageService;

  public TranscriptArchiveDeletionWorker(
      final TranscriptArchiveLifecycleRepository lifecycleRepository) {
    this.lifecycleRepository = lifecycleRepository;
  }

  /** Claims and processes a bounded batch of durable deletion requests. */
  @Scheduled(
      fixedDelayString = "${app.call.transcript.archive.deletion-poll-interval-ms:60000}")
  public void processPendingDeletions() {
    if (s3StorageService == null) {
      return;
    }
    final List<DeletionClaim> claims =
        lifecycleRepository.claimDeletions(
            BATCH_SIZE,
            OffsetDateTime.now(ZoneOffset.UTC).plus(CLAIM_LEASE),
            UUID.randomUUID());
    for (final DeletionClaim claim : claims) {
      process(claim);
    }
  }

  private void process(final DeletionClaim claim) {
    try {
      s3StorageService.deleteFile(claim.storageKey());
      lifecycleRepository.completeDeletion(claim);
    } catch (RuntimeException ex) {
      final String error = truncate(ex.getMessage());
      if (isTerminal(ex) || claim.attempts() + 1 >= Math.max(1, maxAttempts)) {
        lifecycleRepository.deadLetterDeletion(claim, error);
        log.error(
            "Transcript archive object deletion dead-lettered key={} type={}",
            claim.storageKey(),
            ex.getClass().getSimpleName());
      } else {
        lifecycleRepository.retryDeletion(
            claim,
            OffsetDateTime.now(ZoneOffset.UTC).plus(retryDelay(claim.attempts())),
            error);
        log.warn(
            "Transcript archive object deletion deferred key={} type={}",
            claim.storageKey(),
            ex.getClass().getSimpleName());
      }
    }
  }

  private static Duration retryDelay(final int completedAttempts) {
    final int shift = Math.min(Math.max(completedAttempts, 0), 12);
    final long seconds = Math.min(
        MAX_RETRY_DELAY.getSeconds(), BASE_RETRY_DELAY.getSeconds() * (1L << shift));
    return Duration.ofSeconds(seconds);
  }

  private static boolean isTerminal(final Throwable failure) {
    Throwable current = failure;
    while (current != null) {
      if (current instanceof S3Exception s3Failure) {
        final int status = s3Failure.statusCode();
        return status >= 400 && status < 500 && status != 408 && status != 429;
      }
      if (current instanceof SdkClientException) {
        return false;
      }
      current = current.getCause();
    }
    return false;
  }

  private static String truncate(final String value) {
    if (value == null || value.length() <= 1000) {
      return value;
    }
    return value.substring(0, 1000);
  }
}
