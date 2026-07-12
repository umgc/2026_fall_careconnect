package com.careconnect.config;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.flyway.FlywayMigrationStrategy;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.flywaydb.core.Flyway;

/**
 * Optional Flyway hook for local {@code ./mvnw flyway:migrate} only.
 * Not used in ECS/production deploys ({@code spring.flyway.enabled=false}).
 */
@Configuration
@Order(1)
@ConditionalOnProperty(name = "spring.flyway.enabled", havingValue = "true")
public class FlywayConfig {

    /**
     * Custom Flyway migration strategy to handle initialization order
     * This ensures migrations run before JPA entity validation
     */
    @Bean
    public FlywayMigrationStrategy flywayMigrationStrategy() {
        return new FlywayMigrationStrategy() {
            @Override
            public void migrate(Flyway flyway) {
                try {
                    // Perform migration with proper error handling
                    flyway.migrate();
                } catch (Exception e) {
                    // Log the error but don't fail startup in development
                    System.err.println("Flyway migration failed: " + e.getMessage());
                    // In production, you might want to fail here
                    // throw new RuntimeException("Database migration failed", e);
                }
            }
        };
    }
}
