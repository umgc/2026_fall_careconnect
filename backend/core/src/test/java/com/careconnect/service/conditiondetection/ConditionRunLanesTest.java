package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for {@link ConditionRunLanes}: one lane per model, no double-queueing of a run that
 * is already queued or running, and clean release when work fails or the lane is shutting down.
 *
 * <p>Most tests inject a lane factory that queues or runs work inline, so they are deterministic
 * and need no threads. One test uses the real default lanes to prove work leaves the caller's
 * thread.</p>
 */
class ConditionRunLanesTest {

    /** Lanes that hold work until the test runs it, keyed by model. */
    private final Map<String, List<Runnable>> held = new HashMap<>();
    private final AtomicInteger lanesCreated = new AtomicInteger();
    private final ConditionRunLanes holdingLanes = new ConditionRunLanes(modelId -> {
        lanesCreated.incrementAndGet();
        return work -> held.computeIfAbsent(modelId, k -> new ArrayList<>()).add(work);
    });

    /** Scenario: each model gets exactly one lane, reused for its later runs. */
    @Test
    void submit_createsOneLanePerModel() {
        holdingLanes.submit("dam", 1L, () -> { });
        holdingLanes.submit("bedrock", 2L, () -> { });
        holdingLanes.submit("dam", 3L, () -> { });

        assertThat(lanesCreated).hasValue(2);
        assertThat(held.get("dam")).hasSize(2);
        assertThat(held.get("bedrock")).hasSize(1);
    }

    /**
     * Scenario: a due run stays READY until its lane claims it, so the next tick sees it again;
     * it must not be queued twice while the first copy is pending.
     */
    @Test
    void submit_runAlreadyInFlight_isNotQueuedAgain() {
        assertThat(holdingLanes.submit("dam", 1L, () -> { })).isTrue();

        assertThat(holdingLanes.submit("dam", 1L, () -> { })).isFalse();
        assertThat(held.get("dam")).hasSize(1);
    }

    /** Scenario: once a run finishes, the same id can be queued again (e.g. its retry). */
    @Test
    void submit_afterRunCompletes_canBeQueuedAgain() {
        final AtomicInteger runs = new AtomicInteger();
        holdingLanes.submit("dam", 1L, runs::incrementAndGet);
        held.get("dam").remove(0).run();

        assertThat(holdingLanes.submit("dam", 1L, runs::incrementAndGet)).isTrue();
        assertThat(runs).hasValue(1);
    }

    /** Scenario: an unexpected failure is contained (the lane survives) and the id is released. */
    @Test
    void submit_workThrows_isContainedAndReleased() {
        final ConditionRunLanes inline = new ConditionRunLanes(modelId -> Runnable::run);

        final boolean queued = inline.submit("dam", 1L, () -> {
            throw new IllegalStateException("db down");
        });

        assertThat(queued).isTrue();
        assertThat(inline.submit("dam", 1L, () -> { })).isTrue();
    }

    /** Scenario: a lane that rejects work (shutting down) reports false and releases the id. */
    @Test
    void submit_laneRejects_returnsFalseAndReleases() {
        final AtomicInteger calls = new AtomicInteger();
        final Executor rejectFirst = work -> {
            if (calls.getAndIncrement() == 0) {
                throw new RejectedExecutionException("shutting down");
            }
            work.run();
        };
        final ConditionRunLanes lanes = new ConditionRunLanes(modelId -> rejectFirst);

        assertThat(lanes.submit("dam", 1L, () -> { })).isFalse();
        assertThat(lanes.submit("dam", 1L, () -> { })).isTrue();
    }

    /**
     * Scenario: the default lanes run work on a dedicated, named daemon thread, not the caller's
     * (in production the caller is Spring's shared scheduler thread).
     */
    @Test
    void defaultLanes_runOffTheCallerThread() throws InterruptedException {
        // Arrange
        final ConditionRunLanes lanes = new ConditionRunLanes();
        final CountDownLatch done = new CountDownLatch(1);
        final AtomicReference<Thread> ranOn = new AtomicReference<>();

        // Act
        try {
            lanes.submit("kintsugi-dam-3.1", 1L, () -> {
                ranOn.set(Thread.currentThread());
                done.countDown();
            });
            assertThat(done.await(5, TimeUnit.SECONDS)).isTrue();
        } finally {
            lanes.shutdown();
        }

        // Assert
        assertThat(ranOn.get()).isNotSameAs(Thread.currentThread());
        assertThat(ranOn.get().getName()).isEqualTo("condition-kintsugi-dam-3.1");
        assertThat(ranOn.get().isDaemon()).isTrue();
    }

    /** Scenario: shutdown stops executor-backed lanes and ignores plain executors. */
    @Test
    void shutdown_stopsExecutorServiceLanes() {
        final ExecutorService service = Executors.newSingleThreadExecutor();
        final Map<String, Executor> byModel = Map.of("dam", service, "bedrock", Runnable::run);
        final ConditionRunLanes lanes = new ConditionRunLanes(byModel::get);
        lanes.submit("dam", 1L, () -> { });
        lanes.submit("bedrock", 2L, () -> { });

        lanes.shutdown();

        assertThat(service.isShutdown()).isTrue();
    }
}
