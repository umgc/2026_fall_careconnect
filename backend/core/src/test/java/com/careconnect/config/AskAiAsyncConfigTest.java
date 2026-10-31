package com.careconnect.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.atomic.AtomicBoolean;

import org.junit.jupiter.api.Test;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

class AskAiAsyncConfigTest {

    @Test
    void askAiOcrExecutor_usesDropOnRejectInsteadOfCallerRuns() {
        final AskAiAsyncConfig config = new AskAiAsyncConfig();
        final ThreadPoolTaskExecutor taskExecutor =
                (ThreadPoolTaskExecutor) config.askAiOcrExecutor();
        final ThreadPoolExecutor pool = taskExecutor.getThreadPoolExecutor();

        assertThat(pool.getRejectedExecutionHandler())
                .isNotInstanceOf(ThreadPoolExecutor.CallerRunsPolicy.class);

        final AtomicBoolean ran = new AtomicBoolean(false);
        pool.getRejectedExecutionHandler()
                .rejectedExecution(() -> ran.set(true), pool);
        assertThat(ran.get())
                .as("rejected OCR work must be dropped, not executed")
                .isFalse();

        taskExecutor.shutdown();
    }

    @Test
    void retrievalIndexExecutor_runsRejectedWorkOnCallerInsteadOfDropping() {
        final AskAiAsyncConfig config = new AskAiAsyncConfig();
        final ThreadPoolTaskExecutor taskExecutor =
                (ThreadPoolTaskExecutor) config.retrievalIndexExecutor();
        final ThreadPoolExecutor pool = taskExecutor.getThreadPoolExecutor();

        final AtomicBoolean ran = new AtomicBoolean(false);
        pool.getRejectedExecutionHandler()
                .rejectedExecution(() -> ran.set(true), pool);

        assertThat(ran.get())
                .as("rejected indexing work must still run, or the record is never indexed")
                .isTrue();
        taskExecutor.shutdown();
    }
}
