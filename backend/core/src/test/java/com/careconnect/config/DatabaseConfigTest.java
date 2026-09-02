package com.careconnect.config;

import com.careconnect.service.ParameterStoreService;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.mock.env.MockEnvironment;

import javax.sql.DataSource;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link DatabaseConfig}.
 * <p>
 * DatabaseConfig retrieves database credentials (JDBC URL, username, password) from
 * AWS SSM Parameter Store via {@link ParameterStoreService} and builds a HikariCP
 * connection pool. Tests use a Mockito mock for {@code ParameterStoreService} to avoid
 * real AWS network calls, and a {@link MockEnvironment} to supply Hikari pool properties
 * that would normally come from {@code application.yml}. {@code @Value} fields are
 * injected using {@code ReflectionTestUtils} since no Spring context is started.
 */
class DatabaseConfigTest {

    private ParameterStoreService parameterStoreService;
    private DatabaseConfig databaseConfig;

    @BeforeEach
    void setUp() throws Exception {
        // Mock ParameterStoreService to control what "secure parameters" are returned.
        parameterStoreService = mock(ParameterStoreService.class);
        databaseConfig = new DatabaseConfig(parameterStoreService);

        // Inject @Value fields manually since Spring is not managing this bean in tests.
        // The values are SSM parameter key names, not the actual credentials.
        org.springframework.test.util.ReflectionTestUtils.setField(databaseConfig, "jdbcUrl", "db-url-key");
        org.springframework.test.util.ReflectionTestUtils.setField(databaseConfig, "userParameter", "db-user-key");
        org.springframework.test.util.ReflectionTestUtils.setField(databaseConfig, "passwordParameter", "db-pass-key");
    }

    @Test
    void dataSourceProperties_ReturnsCorrectProperties() throws Exception {
        // Verifies that dataSourceProperties() calls getSecureParameter for each of the
        // three credential keys and maps the returned values onto a DataSourceProperties
        // object, which Spring Boot later uses to build the DataSource.
        when(parameterStoreService.getSecureParameter("db-url-key"))
                .thenReturn("jdbc:h2:mem:testdb");
        when(parameterStoreService.getSecureParameter("db-user-key"))
                .thenReturn("sa");
        when(parameterStoreService.getSecureParameter("db-pass-key"))
                .thenReturn("password");

        final DataSourceProperties properties = databaseConfig.dataSourceProperties();

        assertEquals("jdbc:h2:mem:testdb", properties.getUrl());
        assertEquals("sa", properties.getUsername());
        assertEquals("password", properties.getPassword());

        verify(parameterStoreService).getSecureParameter("db-url-key");
        verify(parameterStoreService).getSecureParameter("db-user-key");
        verify(parameterStoreService).getSecureParameter("db-pass-key");
    }

    @Test
    void dataSource_BuildsHikariDataSource() throws Exception {
        // Verifies that dataSource() produces a HikariDataSource with the URL and
        // username from the properties object, confirming the pool is properly wired.
        // H2 in-memory is used as the JDBC URL to avoid needing a real database.
        when(parameterStoreService.getSecureParameter("db-url-key"))
                .thenReturn("jdbc:h2:mem:testdb");
        when(parameterStoreService.getSecureParameter("db-user-key"))
                .thenReturn("sa");
        when(parameterStoreService.getSecureParameter("db-pass-key"))
                .thenReturn("password");

        final DataSourceProperties properties = databaseConfig.dataSourceProperties();

        final MockEnvironment env = new MockEnvironment();
        env.setProperty("spring.datasource.hikari.maximum-pool-size", "5");

        final DataSource dataSource = databaseConfig.dataSource(properties, env);

        assertNotNull(dataSource);
        assertTrue(dataSource instanceof HikariDataSource);

        try (HikariDataSource hikari = (HikariDataSource) dataSource) {
            assertEquals("jdbc:h2:mem:testdb", hikari.getJdbcUrl());
            assertEquals("sa", hikari.getUsername());
        }
    }

    @Test
    void dataSourceProperties_HandlesNullParameterServiceGracefully() throws Exception {
        // Documents the expected failure mode when ParameterStoreService is null:
        // a NullPointerException is thrown rather than silently using empty credentials.
        // This is intentional — misconfigured secrets should fail fast at startup.
        final DatabaseConfig configWithoutService = new DatabaseConfig(null);

        org.springframework.test.util.ReflectionTestUtils.setField(configWithoutService, "jdbcUrl", "key1");
        org.springframework.test.util.ReflectionTestUtils.setField(configWithoutService, "userParameter", "key2");
        org.springframework.test.util.ReflectionTestUtils.setField(configWithoutService, "passwordParameter", "key3");

        assertThrows(NullPointerException.class,
                configWithoutService::dataSourceProperties);
    }

    @Test
    void dataSource_BindsHikariPropertiesFromEnvironment() throws Exception {
        // Verifies that Hikari pool settings (e.g. maximum-pool-size) supplied through
        // the Spring Environment are correctly bound to the HikariDataSource, confirming
        // that the binding mechanism in dataSource() works end-to-end.
        when(parameterStoreService.getSecureParameter("db-url-key"))
                .thenReturn("jdbc:h2:mem:testdb");
        when(parameterStoreService.getSecureParameter("db-user-key"))
                .thenReturn("sa");
        when(parameterStoreService.getSecureParameter("db-pass-key"))
                .thenReturn("password");

        final DataSourceProperties properties = databaseConfig.dataSourceProperties();

        final MockEnvironment env = new MockEnvironment();
        env.setProperty("spring.datasource.hikari.maximum-pool-size", "7");

        final DataSource dataSource = databaseConfig.dataSource(properties, env);

        try (HikariDataSource hikari = (HikariDataSource) dataSource) {
            assertEquals(7, hikari.getMaximumPoolSize());
        }
    }
}
