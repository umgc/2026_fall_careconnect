package com.careconnect.service.conditiondetection;

import jakarta.annotation.PreDestroy;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.function.Function;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Runs condition detection work off Spring's shared scheduler thread, one lane per model.
 *
 * <p>Every {@code @Scheduled} job in the app shares one scheduler thread, and a voice analysis
 * can take minutes, so running it on that thread stalled post-call transcription and transcript
 * screening for every call. Each model gets its own single-thread lane: models never wait on each
 * other, and one model still handles one run at a time (the DAM sidecar serves one request at a
 * time anyway).</p>
 */
@Slf4j
@Component
public class ConditionRunLanes {

    private final Function<String, Executor> laneFactory;
    private final Map<String, Executor> lanes = new ConcurrentHashMap<>();
    private final Set<Long> inFlight = ConcurrentHashMap.newKeySet();

    public ConditionRunLanes() {
        this(ConditionRunLanes::newLane);
    }

    /** Tests pass a direct executor so runs complete before {@code submit} returns. */
    ConditionRunLanes(final Function<String, Executor> laneFactory) {
        this.laneFactory = laneFactory;
    }

    /**
     * Queues a run on its model's lane. A run that is already queued or running is not queued
     * again: it stays due (READY) until its lane claims it, so every worker tick sees it.
     *
     * @return true when the run was queued
     */
    public boolean submit(final String modelId, final Long runId, final Runnable work) {
        if (!inFlight.add(runId)) {
            return false;
        }
        try {
            lanes.computeIfAbsent(modelId, laneFactory).execute(() -> runAndRelease(runId, work));
            return true;
        } catch (RejectedExecutionException shuttingDown) {
            inFlight.remove(runId);
            return false;
        }
    }

    private void runAndRelease(final Long runId, final Runnable work) {
        try {
            work.run();
        } catch (RuntimeException unexpected) {
            // Adapter failures are handled inside processRun; this is a DB or programming error.
            // The run's lease expires and a later tick retries it.
            if (log.isWarnEnabled()) {
                log.warn("Condition run {} stopped unexpectedly: {}",
                        runId, unexpected.getClass().getSimpleName());
            }
        } finally {
            inFlight.remove(runId);
        }
    }

    private static Executor newLane(final String modelId) {
        return Executors.newSingleThreadExecutor(runnable -> {
            final Thread thread = new Thread(runnable, "condition-" + modelId);
            thread.setDaemon(true);
            return thread;
        });
    }

    /** Interrupts in-progress runs on shutdown; their leases expire and they are retried. */
    @PreDestroy
    public void shutdown() {
        lanes.values().forEach(lane -> {
            if (lane instanceof ExecutorService service) {
                service.shutdownNow();
            }
        });
    }
}
