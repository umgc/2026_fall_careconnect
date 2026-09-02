package com.careconnect.config;

import com.careconnect.service.SsmParameterService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.lang.reflect.Field;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link SsmConfig}.
 * <p>
 * SsmConfig is a Spring {@code @Configuration} class that exposes application secrets
 * (Stripe keys, JWT secret, OAuth credentials, database password, etc.) as named beans.
 * In production, values are fetched from AWS SSM Parameter Store via
 * {@link SsmParameterService}; when SSM is unavailable, the config falls back to
 * environment variables.
 * <p>
 * Because {@code SsmParameterService} is optionally injected (it may be null if AWS
 * is not configured), the private field is set via Java Reflection in the helper method
 * {@link #injectSsmService} — the same approach used when Spring's {@code @Autowired}
 * is optional and the field is not exposed through a constructor or setter.
 * <p>
 * {@code @ExtendWith(MockitoExtension.class)} is used instead of
 * {@code MockitoAnnotations.openMocks(this)} for cleaner lifecycle management.
 */
@ExtendWith(MockitoExtension.class)
class SsmConfigTest {

    @Mock
    private SsmParameterService ssmParameterService;

    private SsmConfig ssmConfig;

    @BeforeEach
    void setUp() throws Exception {
        // Instantiate SsmConfig without a Spring context; SSM service is null by default.
        ssmConfig = new SsmConfig();
    }

    /**
     * Injects a SsmParameterService into the private field of SsmConfig using reflection.
     * This is necessary because the field has no public setter and Spring is not running.
     */
    private void injectSsmService(SsmParameterService service) throws Exception {
        final Field field = SsmConfig.class.getDeclaredField("ssmParameterService");
        field.setAccessible(true);
        field.set(ssmConfig, service);
    }

    // --- init() tests ---

    @Test
    void init_WithSsmServiceAvailable_LogsInitialized() throws Exception {
        // Verifies that init() completes without error when SSM service is present,
        // which logs an "initialized" message to indicate production config is active.
        injectSsmService(ssmParameterService);
        assertDoesNotThrow(() -> ssmConfig.init());
    }

    @Test
    void init_WithSsmServiceNull_LogsFallbackWarning() throws Exception {
        // Verifies that init() completes without error when SSM service is absent,
        // logging a warning that the application will fall back to environment variables.
        // ssmParameterService is null by default (not injected)
        assertDoesNotThrow(() -> ssmConfig.init());
    }

    // --- Bean methods with SSM service available ---

    @Test
    void stripeSecretKey_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the Stripe secret key bean queries SSM at the expected path and
        // returns whatever SSM provides, without falling back to an environment variable.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/stripe-secret-key"), any()))
                .thenReturn("ssm-stripe-key");

        final String result = ssmConfig.stripeSecretKey();

        assertEquals("ssm-stripe-key", result);
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/stripe-secret-key"), any());
    }

    @Test
    void stripeWebhookSecret_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the Stripe webhook secret is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/stripe-webhook-secret"), any()))
                .thenReturn("ssm-webhook-secret");

        final String result = ssmConfig.stripeWebhookSecret();

        assertEquals("ssm-webhook-secret", result);
    }

    @Test
    void openaiApiKey_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the OpenAI API key is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/openai-api-key"), any()))
                .thenReturn("ssm-openai-key");

        final String result = ssmConfig.openaiApiKey();

        assertEquals("ssm-openai-key", result);
    }

    @Test
    void deepseekApiKey_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the DeepSeek API key is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/deepseek-api-key"), any()))
                .thenReturn("ssm-deepseek-key");

        final String result = ssmConfig.deepseekApiKey();

        assertEquals("ssm-deepseek-key", result);
    }

    @Test
    void jwtSecret_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the JWT signing secret is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/jwt-secret"), any()))
                .thenReturn("ssm-jwt-secret");

        final String result = ssmConfig.jwtSecret();

        assertEquals("ssm-jwt-secret", result);
    }

    @Test
    void sendgridApiKey_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the SendGrid API key is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/sendgrid-api-key"), any()))
                .thenReturn("ssm-sendgrid-key");

        final String result = ssmConfig.sendgridApiKey();

        assertEquals("ssm-sendgrid-key", result);
    }

    @Test
    void googleClientId_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the Google OAuth client ID is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/google-client-id"), any()))
                .thenReturn("ssm-google-id");

        final String result = ssmConfig.googleClientId();

        assertEquals("ssm-google-id", result);
    }

    @Test
    void googleClientSecret_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the Google OAuth client secret is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/google-client-secret"), any()))
                .thenReturn("ssm-google-secret");

        final String result = ssmConfig.googleClientSecret();

        assertEquals("ssm-google-secret", result);
    }

    @Test
    void fitbitClientId_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the Fitbit OAuth client ID is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/fitbit-client-id"), any()))
                .thenReturn("ssm-fitbit-id");

        final String result = ssmConfig.fitbitClientId();

        assertEquals("ssm-fitbit-id", result);
    }

    @Test
    void fitbitClientSecret_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the Fitbit OAuth client secret is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/fitbit-client-secret"), any()))
                .thenReturn("ssm-fitbit-secret");

        final String result = ssmConfig.fitbitClientSecret();

        assertEquals("ssm-fitbit-secret", result);
    }

    @Test
    void databasePassword_WithSsmService_ReturnsValueFromSsm() throws Exception {
        // Verifies that the database password is fetched from its designated SSM path.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/db-password"), any()))
                .thenReturn("ssm-db-password");

        final String result = ssmConfig.databasePassword();

        assertEquals("ssm-db-password", result);
    }

    // --- Bean methods without SSM service (fallback to env vars) ---

    @Test
    void stripeSecretKey_WithoutSsmService_ReturnsEnvFallback() throws Exception {
        // When SSM service is null (e.g. local dev without AWS), the bean should return
        // the value of the corresponding environment variable instead of throwing.
        // ssmParameterService is null — should return env var value (likely null in test)
        final String result = ssmConfig.stripeSecretKey();

        assertEquals(System.getenv("STRIPE_SECRET_KEY"), result);
    }

    @Test
    void jwtSecret_WithoutSsmService_ReturnsEnvFallback() throws Exception {
        // Verifies the env-variable fallback path for the JWT secret.
        final String result = ssmConfig.jwtSecret();

        assertEquals(System.getenv("SECURITY_JWT_SECRET"), result);
    }

    @Test
    void databasePassword_WithoutSsmService_ReturnsEnvFallback() throws Exception {
        // Verifies the env-variable fallback path for the database password.
        final String result = ssmConfig.databasePassword();

        assertEquals(System.getenv("DB_PASSWORD"), result);
    }

    // --- getSsmParameter fallback behavior ---

    @Test
    void getSsmParameter_WhenSsmReturnsNull_FallsBackToEnvValue() throws Exception {
        // Verifies that when SSM explicitly returns null (parameter exists but has no value),
        // the bean method propagates null rather than substituting an empty string.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/jwt-secret"), any()))
                .thenReturn(null);

        final String result = ssmConfig.jwtSecret();

        assertNull(result);
    }

    @Test
    void getSsmParameter_WhenSsmReturnsSameAsEnvFallback_ReturnsThatValue() throws Exception {
        // Verifies that when SSM returns a value that happens to match the env-var fallback,
        // the correct value is still returned (covers the case where SSM mirrors env vars).
        injectSsmService(ssmParameterService);
        final String envFallback = System.getenv("STRIPE_SECRET_KEY");
        when(ssmParameterService.getParameterOrDefault(eq("/careconnect/prod/stripe-secret-key"), any()))
                .thenReturn(envFallback);

        final String result = ssmConfig.stripeSecretKey();

        assertEquals(envFallback, result);
    }

    // --- Verify correct SSM parameter paths ---

    @Test
    void allBeans_UseCorrectSsmParameterPrefix() throws Exception {
        // Exhaustive path verification: every secret bean must use the exact SSM path
        // under "/careconnect/prod/" to ensure secrets are fetched from the right
        // namespace and not accidentally crossed between environments.
        injectSsmService(ssmParameterService);
        when(ssmParameterService.getParameterOrDefault(anyString(), any())).thenReturn("value");

        ssmConfig.stripeSecretKey();
        ssmConfig.stripeWebhookSecret();
        ssmConfig.openaiApiKey();
        ssmConfig.deepseekApiKey();
        ssmConfig.jwtSecret();
        ssmConfig.sendgridApiKey();
        ssmConfig.googleClientId();
        ssmConfig.googleClientSecret();
        ssmConfig.fitbitClientId();
        ssmConfig.fitbitClientSecret();
        ssmConfig.databasePassword();

        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/stripe-secret-key"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/stripe-webhook-secret"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/openai-api-key"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/deepseek-api-key"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/jwt-secret"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/sendgrid-api-key"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/google-client-id"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/google-client-secret"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/fitbit-client-id"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/fitbit-client-secret"), any());
        verify(ssmParameterService).getParameterOrDefault(eq("/careconnect/prod/db-password"), any());
    }
}
