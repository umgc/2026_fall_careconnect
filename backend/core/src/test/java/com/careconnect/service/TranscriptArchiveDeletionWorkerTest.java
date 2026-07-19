package com.careconnect.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.repository.TranscriptArchiveLifecycleRepository;
import com.careconnect.repository.TranscriptArchiveLifecycleRepository.DeletionClaim;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class TranscriptArchiveDeletionWorkerTest {

  private static final UUID TOKEN =
      UUID.fromString("00000000-0000-0000-0000-000000000123");
  private static final DeletionClaim CLAIM =
      new DeletionClaim(1L, "transcripts/archive.json", TOKEN);

  @Mock private TranscriptArchiveLifecycleRepository lifecycleRepository;
  @Mock private S3StorageService s3StorageService;

  private TranscriptArchiveDeletionWorker worker;

  @BeforeEach
  void setUp() {
    worker = new TranscriptArchiveDeletionWorker(lifecycleRepository);
    ReflectionTestUtils.setField(worker, "s3StorageService", s3StorageService);
  }

  @Test
  void successfulObjectDeleteCompletesOwnedOutboxLease() {
    when(lifecycleRepository.claimDeletions(eq(25), any(), any()))
        .thenReturn(List.of(CLAIM));

    worker.processPendingDeletions();

    verify(s3StorageService).deleteFile(CLAIM.storageKey());
    verify(lifecycleRepository).completeDeletion(CLAIM);
  }

  @Test
  void failedObjectDeleteRemainsDurableForRetry() {
    when(lifecycleRepository.claimDeletions(eq(25), any(), any()))
        .thenReturn(List.of(CLAIM));
    org.mockito.Mockito.doThrow(new RuntimeException("S3 unavailable"))
        .when(s3StorageService)
        .deleteFile(CLAIM.storageKey());

    worker.processPendingDeletions();

    verify(lifecycleRepository)
        .retryDeletion(eq(CLAIM), any(), eq("S3 unavailable"));
  }
}
