package com.careconnect.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.context.support.GenericApplicationContext;
import org.springframework.mock.env.MockEnvironment;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;
import software.amazon.awssdk.services.ssm.model.Parameter;

import java.lang.reflect.Method;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;

/**
 * Unit tests for {@link SsmPropertySourceInitializer}.
 * <p>
 * SsmPropertySourceInitializer is a Spring {@code ApplicationContextInitializer} that
 * runs very early in startup (before beans are created) to load secrets from AWS SSM
 * Parameter Store into a custom {@code PropertySource}. It only activates when:
 * <ol>
 *   <li>The active Spring profile is {@code prod}.</li>
 *   <li>The property {@code careconnect.aws.enabled} is not {@code false}.</li>
 * </ol>
 * <p>
 * Profile-gating tests use {@link MockEnvironment} to control active profiles without
 * starting a full Spring context. The private {@code loadParametersFromSsm} method is
 * accessed via Java Reflection ({@link Method#setAccessible}) to test the SSM-fetching
 * logic in isolation — this is justified because the method encapsulates complex I/O
 * behaviour that is impractical to exercise indirectly through the public {@code initialize}
 * method without a real AWS connection.
 */
class SsmPropertySourceInitializerTest {

    private SsmPropertySourceInitializer initializer;
    private GenericApplicationContext context;
    private MockEnvironment environment;

    @BeforeEach
    void setup() throws Exception {
        // Use a GenericApplicationContext so we can set a MockEnvironment on it.
        // MockEnvironment allows programmatic control of active profiles and properties.
        initializer = new SsmPropertySourceInitializer();
        context = new GenericApplicationContext();
        environment = new MockEnvironment();
        context.setEnvironment(environment);
    }

    // ==========================================
    // Should NOT initialize if not prod
    // ==========================================

    @Test
    void shouldNotInitializeIfNotProdProfile() throws Exception {
        // Verifies the profile guard: when the active profile is "dev" (not "prod"),
        // the initializer does not add the "ssmPropertySource" to the environment,
        // keeping local development free of AWS dependencies.
        environment.setActiveProfiles("dev");

        initializer.initialize(context);

        assertNull(environment.getPropertySources().get("ssmPropertySource"));
    }

    // ==========================================
    // Should NOT initialize if AWS disabled
    // ==========================================

    @Test
    void shouldNotInitializeIfAwsDisabled() throws Exception {
        // Verifies the AWS-enabled guard: even on the "prod" profile, the initializer
        // skips SSM loading when careconnect.aws.enabled=false, supporting deployments
        // that run in production-like environments without AWS (e.g. Docker Compose).
        environment.setActiveProfiles("prod");
        environment.setProperty("careconnect.aws.enabled", "false");

        initializer.initialize(context);

        assertNull(environment.getPropertySources().get("ssmPropertySource"));
    }

    // ==========================================
    // Test loadParametersFromSsm (via reflection)
    // ==========================================

    @Test
    void shouldLoadParametersFromSsm() throws Exception {
        // Verifies that loadParametersFromSsm() correctly maps an SSM parameter name
        // (e.g. "/careconnect/prod/stripe-secret-key") to a Spring-friendly property
        // key (e.g. "stripe.secret-key") and stores its value in the returned map.
        // Reflection is used because the method is private — it cannot be tested via
        // the public API without a full AWS-connected prod environment.

        // Mock SSM Client to return a controlled parameter value
        final SsmClient ssmClient = Mockito.mock(SsmClient.class);

        final Parameter mockParameter = Parameter.builder()
                .name("/careconnect/prod/stripe-secret-key")
                .value("test-secret")
                .build();

        final GetParameterResponse response = GetParameterResponse.builder()
                .parameter(mockParameter)
                .build();

        Mockito.when(ssmClient.getParameter(any(GetParameterRequest.class)))
                .thenReturn(response);

        // Access private method using reflection
        final Method method = SsmPropertySourceInitializer.class
                .getDeclaredMethod("loadParametersFromSsm", SsmClient.class, String.class);

        method.setAccessible(true);

        @SuppressWarnings("unchecked") final Map<String, Object> result =
                (Map<String, Object>) method.invoke(initializer, ssmClient, "/careconnect/prod/");

        assertFalse(result.isEmpty());
        assertTrue(result.containsKey("stripe.secret-key"));
        assertEquals("test-secret", result.get("stripe.secret-key"));
    }

    // ==========================================
    // Should Handle Missing Parameter
    // ==========================================

    @Test
    void shouldHandleMissingParameterGracefully() throws Exception {
        // Verifies that when SSM throws (e.g. the parameter does not exist or access is
        // denied), loadParametersFromSsm() returns an empty map rather than propagating
        // the exception — preventing a single missing secret from crashing startup.

        final SsmClient ssmClient = Mockito.mock(SsmClient.class);

        Mockito.when(ssmClient.getParameter(any(GetParameterRequest.class)))
                .thenThrow(new RuntimeException("Parameter not found"));

        final Method method = SsmPropertySourceInitializer.class
                .getDeclaredMethod("loadParametersFromSsm", SsmClient.class, String.class);

        method.setAccessible(true);

        @SuppressWarnings("unchecked") final Map<String, Object> result =
                (Map<String, Object>) method.invoke(initializer, ssmClient, "/careconnect/prod/");

        assertTrue(result.isEmpty());
    }

    // ==========================================
    // Should NOT initialize with no active profiles
    // ==========================================

    @Test
    void shouldNotInitializeWhenNoActiveProfilesSet() throws Exception {
        // Verifies the profile guard with no profiles set at all (empty array).
        // MockEnvironment has no active profiles by default, so "prod" is absent.
        initializer.initialize(context);

        assertNull(environment.getPropertySources().get("ssmPropertySource"));
    }

    // ==========================================
    // Should NOT initialize when profile is "test"
    // ==========================================

    @Test
    void shouldNotInitializeWhenProfileIsTest() throws Exception {
        // Verifies the profile guard works for any non-prod profile, not just "dev".
        environment.setActiveProfiles("test");

        initializer.initialize(context);

        assertNull(environment.getPropertySources().get("ssmPropertySource"));
    }

    // ==========================================
    // Should attempt initialization on prod (graceful failure without real AWS)
    // ==========================================

    @Test
    void shouldNotCrashWhenProdAndAwsEnabledDefaultButNoRealAws() throws Exception {
        // Verifies the outer try/catch in initialize(): when on "prod" with the default
        // careconnect.aws.enabled (not set → defaults to "true"), the initializer
        // attempts to contact AWS SSM. In a test environment without real AWS credentials
        // or region configured, the SDK throws (e.g. SdkClientException for missing
        // region). The outer catch block must absorb this and not propagate — startup
        // must never be blocked by a missing secret store.
        environment.setActiveProfiles("prod");
        // careconnect.aws.enabled not set; defaults to "true" inside initialize()

        assertDoesNotThrow(() -> initializer.initialize(context));
        // Either the exception path (no AWS) or the empty-map path (AWS reachable but
        // no params) is taken; in neither case should a property source be added.
        assertNull(environment.getPropertySources().get("ssmPropertySource"));
    }

    @Test
    void shouldNotCrashWhenProdAndAwsEnabledExplicitlyTrueButNoRealAws() throws Exception {
        // Same as above but with careconnect.aws.enabled explicitly set to "true",
        // exercising the branch where the string comparison passes and the guard is
        // not triggered. Covers the prod+enabled code path in initialize().
        environment.setActiveProfiles("prod");
        environment.setProperty("careconnect.aws.enabled", "true");

        assertDoesNotThrow(() -> initializer.initialize(context));
        assertNull(environment.getPropertySources().get("ssmPropertySource"));
    }

    // ==========================================
    // Load ALL parameters when all SSM calls succeed
    // ==========================================

    @Test
    void shouldLoadAllParametersWhenAllSsmCallsSucceed() throws Exception {
        // Verifies that loadParametersFromSsm() iterates every entry in SSM_PARAMETERS
        // and populates the map with the matching Spring property key from
        // PARAMETER_MAPPING. JWT and DB credentials are excluded (ECS Secrets Manager).
        // With 12 parameters defined and all calls succeeding, the result must contain
        // exactly 12 entries.

        final SsmClient ssmClient = Mockito.mock(SsmClient.class);

        final GetParameterResponse response = GetParameterResponse.builder()
                .parameter(Parameter.builder()
                        .name("irrelevant-name")
                        .value("mock-value")
                        .build())
                .build();

        Mockito.when(ssmClient.getParameter(any(GetParameterRequest.class)))
                .thenReturn(response);

        final Method method = SsmPropertySourceInitializer.class
                .getDeclaredMethod("loadParametersFromSsm", SsmClient.class, String.class);
        method.setAccessible(true);

        @SuppressWarnings("unchecked") final Map<String, Object> result =
                (Map<String, Object>) method.invoke(initializer, ssmClient, "/careconnect/prod/");

        // All 12 SSM_PARAMETERS entries are in PARAMETER_MAPPING, so all should load.
        assertEquals(12, result.size());

        // Spot-check a representative sample of the PARAMETER_MAPPING entries.
        assertEquals("mock-value", result.get("stripe.secret-key"));
        assertEquals("mock-value", result.get("stripe.webhook-secret"));
        assertEquals("mock-value", result.get("careconnect.email.sendgrid.api-key"));
        assertFalse(result.containsKey("security.jwt.secret"));
        assertFalse(result.containsKey("careconnect.db.password"));
        assertEquals("mock-value", result.get("aws.s3.access-key"));
        assertEquals("mock-value", result.get("aws.s3.secret-key"));
        assertEquals("mock-value", result.get("firebase.service-account-key"));
    }

    // ==========================================
    // resolveSsmPrefix
    // ==========================================

    @Test
    void resolveSsmPrefix_usesEnvironmentWhenSet() {
        environment.setProperty("ENVIRONMENT", "cfdemo");
        assertEquals("/careconnect/cfdemo/", SsmPropertySourceInitializer.resolveSsmPrefix(environment));
    }

    @Test
    void resolveSsmPrefix_defaultsToProdWhenEnvironmentUnset() {
        assertEquals("/careconnect/prod/", SsmPropertySourceInitializer.resolveSsmPrefix(environment));
    }

    @Test
    void resolveSsmPrefix_explicitOverrideAddsTrailingSlash() {
        environment.setProperty("CARECONNECT_SSM_PREFIX", "/custom/path");
        assertEquals("/custom/path/", SsmPropertySourceInitializer.resolveSsmPrefix(environment));
    }

    @Test
    void resolveSsmPrefix_explicitOverridePreservesTrailingSlash() {
        environment.setProperty("CARECONNECT_SSM_PREFIX", "/custom/path/");
        assertEquals("/custom/path/", SsmPropertySourceInitializer.resolveSsmPrefix(environment));
    }

    // ==========================================
    // Partial load: some parameters succeed, some fail
    // ==========================================

    @Test
    void shouldLoadOnlySuccessfulParametersWhenSomeSsmCallsFail() throws Exception {
        // Verifies that individual parameter failures do not abort the loop: the first
        // SSM call succeeds (stripe-secret-key) and all subsequent calls throw, so the
        // returned map contains exactly the one successfully fetched property.

        final SsmClient ssmClient = Mockito.mock(SsmClient.class);

        final GetParameterResponse firstResponse = GetParameterResponse.builder()
                .parameter(Parameter.builder()
                        .name("/careconnect/prod/stripe-secret-key")
                        .value("only-this-one")
                        .build())
                .build();

        Mockito.when(ssmClient.getParameter(any(GetParameterRequest.class)))
                .thenReturn(firstResponse)
                .thenThrow(new RuntimeException("Access denied"));

        final Method method = SsmPropertySourceInitializer.class
                .getDeclaredMethod("loadParametersFromSsm", SsmClient.class, String.class);
        method.setAccessible(true);

        @SuppressWarnings("unchecked") final Map<String, Object> result =
                (Map<String, Object>) method.invoke(initializer, ssmClient, "/careconnect/prod/");

        assertEquals(1, result.size());
        assertTrue(result.containsKey("stripe.secret-key"));
        assertEquals("only-this-one", result.get("stripe.secret-key"));
    }
}
