package com.careconnect.config;

import java.util.concurrent.Executor;
import java.util.concurrent.ThreadPoolExecutor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/**
 * Bounded executors for Ask AI background work (OCR must not use the unbounded
 * default {@code @Async} executor).
 */
@Configuration
public class AskAiAsyncConfig {

    public static final String ASK_AI_OCR_EXECUTOR = "askAiOcrExecutor";

    @Bean(name = ASK_AI_OCR_EXECUTOR)
    public Executor askAiOcrExecutor() {
        final ThreadPoolTaskExecutor exec = new ThreadPoolTaskExecutor();
        exec.setCorePoolSize(2);
        exec.setMaxPoolSize(4);
        exec.setQueueCapacity(50);
        exec.setThreadNamePrefix("ask-ai-ocr-");
        exec.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        exec.initialize();
        return exec;
    }
}
