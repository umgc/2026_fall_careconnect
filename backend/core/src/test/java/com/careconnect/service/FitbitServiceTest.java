package com.careconnect.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.MockitoAnnotations;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests for {@link FitbitService}.
 * <p>
 * FitbitService is currently an empty shell -- all implementation is commented out.
 * These tests verify that the class can be instantiated and that the Spring-managed
 * bean contract (default no-arg constructor) is intact.
 */
class FitbitServiceTest {

    private FitbitService fitbitService;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        fitbitService = new FitbitService();
    }

    @Test
    @DisplayName("constructor_defaultNoArg_createsNonNullInstance")
    void constructor_defaultNoArg_createsNonNullInstance() throws Exception {
        assertThat(fitbitService).isNotNull();
    }

    @Test
    @DisplayName("class_springServiceAnnotation_isInstantiableAsBean")
    void class_springServiceAnnotation_isInstantiableAsBean() throws Exception {
        // Verify a second independent instance can be created (bean-style)
        final FitbitService anotherInstance = new FitbitService();
        assertThat(anotherInstance).isNotNull();
        assertThat(anotherInstance).isNotSameAs(fitbitService);
    }
}
