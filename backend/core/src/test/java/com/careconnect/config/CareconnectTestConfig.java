package com.careconnect.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;

import com.careconnect.security.JwtTokenProvider;
import com.careconnect.service.AIChatService;
import com.careconnect.websocket.CallNotificationHandler;

import static org.mockito.Mockito.mock;

/**
 * Shared Spring test configuration for integration tests that run under the "test" profile.
 * <p>
 * This class is annotated with {@link TestConfiguration} so it is only loaded in test
 * contexts — never in production. It is also gated by {@code @Profile("test")} so it
 * is only active when the "test" profile is explicitly set, preventing accidental
 * inclusion in integration tests that use different profiles.
 * <p>
 * Each bean is annotated with {@link Primary} so that Spring prefers these mock
 * implementations over any real beans of the same type that may be on the classpath.
 * This is the standard pattern for replacing infrastructure dependencies (JWT, WebSocket
 * handlers) with no-op Mockito mocks in tests that do not need to exercise those concerns.
 */
@TestConfiguration
@Profile("test")
public class CareconnectTestConfig {

    /**
     * Provides a Mockito mock of {@link JwtTokenProvider} as the primary bean.
     * Tests that import this config can stub the mock's behaviour without triggering
     * real JWT parsing or validation, which would require a real secret key.
     */
    @Bean
    @Primary
    public JwtTokenProvider mockJwtTokenProvider() {
        return mock(JwtTokenProvider.class);
    }

    /**
     * Provides a Mockito mock of {@link CallNotificationHandler} as the primary bean.
     * This prevents tests from needing a real WebSocket handler when
     * {@link WebSocketConfig} tries to register it — the mock satisfies the dependency
     * without opening any actual WebSocket connections.
     */
    @Bean
    @Primary
    public CallNotificationHandler mockCallNotificationHandler() {
        return mock(CallNotificationHandler.class);
    }

    /**
     * Provides a primary mock for {@link AIChatService} so that beans requiring it
     * (e.g. PatientNotetakerService) always receive a single unambiguous candidate,
     * even when multiple implementations (BedrockAIChatAdapter, MockAIChatService)
     * are on the classpath.
     */
    @Bean
    @Primary
    public AIChatService primaryMockAIChatService() {
        return mock(AIChatService.class);
    }
}
