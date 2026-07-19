package com.careconnect.repository.retrieval;

import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Re-runs PostgreSQL repository contracts as mandatory tests on CI hosts.
 *
 * <p>The developer test class may skip when Docker is absent; this CI specialization
 * deliberately fails instead, preventing PostgreSQL-only SQL regressions from merging.
 */
@EnabledIfEnvironmentVariable(named = "CI", matches = "(?i)true")
@Testcontainers
class RetrievalIndexChunkRepositoryPostgresCiTest
        extends RetrievalIndexChunkRepositoryPostgresTest {
}
