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

/** Idempotently removes transcript archive objects requested by committed database changes. */
@Slf4j
@Service
public class TranscriptArchiveDeletionWorker {

  private static final int BATCH_SIZE = 25;
  private static final Duration CLAIM_LEASE = Duration.ofMinutes(5);
  private static final Duration RETRY_DELAY = Duration.ofMinutes(5);

  private final TranscriptArchiveLifecycleRepository lifecycleRepository;

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
      lifecycleRepository.retryDeletion(
          claim,
          OffsetDateTime.now(ZoneOffset.UTC).plus(RETRY_DELAY),
          truncate(ex.getMessage()));
      log.warn(
          "Transcript archive object deletion deferred key={} type={}",
          claim.storageKey(),
          ex.getClass().getSimpleName());
    }
  }

  private static String truncate(final String value) {
    if (value == null || value.length() <= 1000) {
      return value;
    }
    return value.substring(0, 1000);
  }
}
