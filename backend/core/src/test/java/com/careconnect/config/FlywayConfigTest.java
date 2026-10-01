package com.careconnect.config;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.boot.autoconfigure.flyway.FlywayMigrationStrategy;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for FlywayConfig.
 * <p>
 * Verifies:
 * - Bean creation
 * - Successful migration execution
 * - Exception handling behavior
 */
class FlywayConfigTest {

    private FlywayConfig flywayConfig;

    @Mock
    private Flyway flyway;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        flywayConfig = new FlywayConfig();
    }

    @Test
    void flywayMigrationStrategyBeanIsCreated() throws Exception {
        final FlywayMigrationStrategy strategy = flywayConfig.flywayMigrationStrategy();
        assertNotNull(strategy);
    }

    @Test
    void migrate_CallsFlywayMigrateSuccessfully() throws Exception {
        final FlywayMigrationStrategy strategy = flywayConfig.flywayMigrationStrategy();

        assertDoesNotThrow(() -> strategy.migrate(flyway));

        verify(flyway, times(1)).migrate();
    }

    @Test
    void migrate_CatchesExceptionAndDoesNotThrow() throws Exception {
        final FlywayMigrationStrategy strategy = flywayConfig.flywayMigrationStrategy();

        doThrow(new RuntimeException("Migration failure"))
                .when(flyway)
                .migrate();

        // Should NOT throw
        assertDoesNotThrow(() -> strategy.migrate(flyway));

        verify(flyway, times(1)).migrate();
    }
}
