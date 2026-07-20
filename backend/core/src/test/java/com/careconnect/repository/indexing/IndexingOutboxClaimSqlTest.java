package com.careconnect.repository.indexing;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Contract tests for indexing_outbox claim lease SQL (Task 4.1 / multi-ECS safety).
 */
class IndexingOutboxClaimSqlTest {

    @Test
    @DisplayName("claim query uses make_interval for integer leaseMinutes binding")
    void claimQuery_usesMakeInterval() throws Exception {
        final String source = Files.readString(
                Path.of("src/main/java/com/careconnect/repository/indexing/IndexingOutboxRepository.java"),
                StandardCharsets.UTF_8);

        assertThat(source).contains("make_interval(mins => :leaseMinutes)");
        assertThat(source).doesNotContain(":leaseMinutes || ' minutes'");
        assertThat(source).contains("FOR UPDATE SKIP LOCKED");
        assertThat(source).contains("claimed_at IS NULL");
    }
}
