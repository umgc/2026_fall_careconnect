package com.careconnect.config;

import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionHandler;
import java.util.concurrent.ThreadPoolExecutor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/**
 * Bounded executors for Ask AI background work (OCR must not use the unbounded
 * default {@code @Async} executor).
 */
@Configuration
public class AskAiAsyncConfig {

    private static final Logger log = LoggerFactory.getLogger(AskAiAsyncConfig.class);

    public static final String ASK_AI_OCR_EXECUTOR = "askAiOcrExecutor";

    @Bean(name = ASK_AI_OCR_EXECUTOR)
    public Executor askAiOcrExecutor() {
        final ThreadPoolTaskExecutor exec = new ThreadPoolTaskExecutor();
        exec.setCorePoolSize(2);
        exec.setMaxPoolSize(4);
        exec.setQueueCapacity(50);
        exec.setThreadNamePrefix("ask-ai-ocr-");
        // Never run Textract on the request/afterCommit thread when the queue is full.
        final RejectedExecutionHandler reject = (Runnable r, ThreadPoolExecutor executor) ->
                log.warn(
                        "Ask AI OCR queue full (active={} queue={}); dropping OCR task",
                        executor.getActiveCount(),
                        executor.getQueue().size());
        exec.setRejectedExecutionHandler(reject);
        exec.initialize();
        return exec;
    }
}
