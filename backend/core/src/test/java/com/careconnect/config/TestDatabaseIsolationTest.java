package com.careconnect.config;

import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.test.context.ConfigDataApplicationContextInitializer;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;

/** Checks the real test profile without loading the application's external services. */
class TestDatabaseIsolationTest {

    @Test
    void independentContextsCannotDropEachOthersTables() {
        final ApplicationContextRunner runner = new ApplicationContextRunner()
                .withInitializer(new ConfigDataApplicationContextInitializer())
                .withPropertyValues("spring.profiles.active=test")
                .withConfiguration(AutoConfigurations.of(DataSourceAutoConfiguration.class));

        runner.run(first -> runner.run(second -> {
            assertThat(first).hasNotFailed();
            assertThat(second).hasNotFailed();
            try (var firstConnection = first.getBean(DataSource.class).getConnection();
                    var secondConnection = second.getBean(DataSource.class).getConnection();
                    var firstSql = firstConnection.createStatement();
                    var secondSql = secondConnection.createStatement()) {
                assertThat(firstConnection.getMetaData().getURL())
                        .isNotEqualTo(secondConnection.getMetaData().getURL());
                firstSql.execute("CREATE TABLE isolation_probe (id INT)");
                secondSql.execute("CREATE TABLE isolation_probe (id INT)");
                secondSql.execute("INSERT INTO isolation_probe VALUES (42)");
                // Model the schema cleanup performed by Hibernate's create-drop lifecycle.
                firstSql.execute("DROP ALL OBJECTS");
                try (var rows = secondSql.executeQuery("SELECT id FROM isolation_probe")) {
                    assertThat(rows.next()).isTrue();
                    assertThat(rows.getInt(1)).isEqualTo(42);
                }
            }
        }));
    }
}
