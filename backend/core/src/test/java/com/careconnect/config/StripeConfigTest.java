package com.careconnect.config;

import com.stripe.Stripe;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link StripeConfig}.
 * <p>
 * StripeConfig is a Spring {@code @Configuration} class whose {@code @PostConstruct}
 * {@code init()} method assigns the Stripe secret key to the static {@link Stripe#apiKey}
 * field — the global hook used by the Stripe Java SDK for every API call.
 * <p>
 * Because {@code Stripe.apiKey} is a static field, its state persists across tests.
 * {@code @AfterEach cleanup()} resets it to {@code null} to prevent test pollution.
 * <p>
 * The {@code secretKey} field of {@link StripeConfig} is private and annotated with
 * {@code @Value}; since Spring is not running, Java Reflection is used to inject test
 * values directly, allowing controlled verification of the blank-key guard and the
 * key-assignment happy path.
 */
class StripeConfigTest {

    @AfterEach
    void cleanup() throws Exception {
        // Reset the static Stripe.apiKey after each test so that one test's assignment
        // does not influence subsequent tests (static state is shared across the JVM).
        Stripe.apiKey = null;
    }

    // ==========================================
    // Should NOT set Stripe key if blank
    // ==========================================

    @Test
    void shouldNotSetStripeApiKeyIfSecretKeyBlank() throws Exception {
        // Verifies that when secretKey is an empty string (e.g. the property is present
        // but unset in the environment), init() leaves Stripe.apiKey as null instead of
        // registering an empty key that would cause all Stripe API calls to fail silently.
        final StripeConfig config = new StripeConfig();

        // Inject blank secretKey using reflection since @Value is not processed here
        final Field field = StripeConfig.class.getDeclaredField("secretKey");
        field.setAccessible(true);
        field.set(config, "");

        config.init();

        assertNull(Stripe.apiKey);
    }

    // ==========================================
    // Should set Stripe key when provided
    // ==========================================

    @Test
    void shouldSetStripeApiKeyWhenSecretKeyPresent() throws Exception {
        // Verifies that when a non-blank secret key is provided, init() assigns it to
        // Stripe.apiKey so subsequent SDK calls are authenticated with that key.
        final StripeConfig config = new StripeConfig();

        final Field field = StripeConfig.class.getDeclaredField("secretKey");
        field.setAccessible(true);
        field.set(config, "sk_test_123");

        config.init();

        assertEquals("sk_test_123", Stripe.apiKey);
    }
}
