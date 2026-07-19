package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.CallSummary;
import com.careconnect.repository.CallSummaryRepository;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.ReentrantLock;
import org.junit.jupiter.api.Test;

class CallSummaryPersistenceServiceTest {

  @Test
  void concurrentDuplicateGeneration_persistsAndEmitsOnce() {
    final CallSummaryRepository repository = mock(CallSummaryRepository.class);
    final IndexingEventEmitter emitter = mock(IndexingEventEmitter.class);
    final CallSummaryPersistenceService service =
        new CallSummaryPersistenceService(repository, emitter);
    final ReentrantLock databaseLock = new ReentrantLock();
    final AtomicReference<CallSummary> stored = new AtomicReference<>();

    doAnswer(
            invocation -> {
              databaseLock.lock();
              return null;
            })
        .when(repository)
        .acquireGenerationLock(any());
    when(repository.findByCallIdAndTranscriptSnapshotVersionAndModelConfigVersion(
            any(), any(), any()))
        .thenAnswer(
            invocation -> {
              final CallSummary existing = stored.get();
              if (existing != null) {
                databaseLock.unlock();
              }
              return Optional.ofNullable(existing);
            });
    when(repository.save(any(CallSummary.class)))
        .thenAnswer(
            invocation -> {
              final CallSummary saved = invocation.getArgument(0);
              saved.setId(101L);
              stored.set(saved);
              databaseLock.unlock();
              return saved;
            });

    final CompletableFuture<CallSummary> first =
        CompletableFuture.supplyAsync(() -> service.persist(summary()));
    final CompletableFuture<CallSummary> second =
        CompletableFuture.supplyAsync(() -> service.persist(summary()));

    assertThat(first.join().getId()).isEqualTo(101L);
    assertThat(second.join().getId()).isEqualTo(101L);
    verify(repository, times(1)).save(any(CallSummary.class));
    verify(emitter, times(1)).emitSummaryCreated(any());
  }

  private static CallSummary summary() {
    final CallSummary summary = new CallSummary();
    summary.setCallId("call-1");
    summary.setPatientId(42L);
    summary.setStatus("SUCCESS");
    summary.setSummaryJson("{\"headline\":\"Stable\"}");
    summary.setGeneratedAt(LocalDateTime.now());
    summary.setTranscriptSegmentCount(2);
    summary.setTranscriptSnapshotVersion("sha256:snapshot");
    summary.setModelConfigVersion("model:config-v2");
    return summary;
  }
}
