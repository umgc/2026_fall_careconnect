package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrResource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Slice;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Proves {@link EhrResourceQueryRepository#findPage} on real PostgreSQL: newest first, undated rows
 * last, the Patient row excluded, rows scoped to one user and one source, and the optional date bounds,
 * including a null bound, which is the case PostgreSQL rejects when a parameter's type is left unknown.
 * <p>
 * PostgreSQL only and opt-in, like the other {@code *PostgresTest} classes, and needs a database the
 * application on this branch has already booted against so {@code ehr_resource} exists. Every test
 * runs in the {@code @DataJpaTest} transaction and is rolled back:
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5432/careconnect \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=EhrResourceQueryRepositoryPostgresTest test
 * </pre>
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@EnabledIfEnvironmentVariable(named = "EHR_IT_JDBC_URI", matches = ".+")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@TestPropertySource(properties = {
        "spring.datasource.url=${EHR_IT_JDBC_URI}",
        "spring.datasource.username=${EHR_IT_DB_USER}",
        "spring.datasource.password=${EHR_IT_DB_PASSWORD}",
        "spring.datasource.driver-class-name=org.postgresql.Driver",
        "spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect",
        "spring.jpa.hibernate.ddl-auto=none",
        "spring.jpa.properties.hibernate.jdbc.time_zone=UTC",
        "spring.flyway.enabled=false",
        "spring.sql.init.mode=never"
})
class EhrResourceQueryRepositoryPostgresTest {

    /** ehr_resource.user_id has no foreign key, so ids no real user holds keep the probe isolated. */
    private static final long USER_ID = 990_000_002L;
    private static final long OTHER_USER_ID = 990_000_003L;
    private static final String SOURCE = "ATHENAHEALTH";

    @Autowired
    private EhrResourceRepository resources;

    @Autowired
    private EhrResourceQueryRepository queries;

    @BeforeEach
    void seed() {
        save(USER_ID, SOURCE, "Condition", "c-new", "2024-06-01T10:00:00Z");
        save(USER_ID, SOURCE, "Condition", "c-mid", "2024-01-15");
        save(USER_ID, SOURCE, "Observation", "o-old", "2023-12-31");
        save(USER_ID, SOURCE, "Condition", "c-undated", null);
        save(USER_ID, SOURCE, "Patient", "p-1", null);
        // Must never appear: another user's row, and this user's row from another source.
        save(OTHER_USER_ID, SOURCE, "Condition", "x-other-user", "2024-07-01");
        save(USER_ID, "EPIC", "Condition", "x-other-source", "2024-08-01");
    }

    private void save(final long userId, final String source, final String type, final String id,
                      final String occurredAt) {
        resources.save(EhrResource.builder().userId(userId).source(source).resourceType(type)
                .resourceFhirId(id).occurredAt(occurredAt).build());
    }

    private static List<String> ids(final Slice<EhrResource> slice) {
        return slice.getContent().stream().map(EhrResource::getResourceFhirId).toList();
    }

    @Test
    @DisplayName("pages newest first with undated rows last, scoped to one user and source, without Patient")
    void pagesNewestFirst() {
        // Act
        final Slice<EhrResource> first = queries.findPage(USER_ID, SOURCE, null, null, PageRequest.of(0, 2));
        final Slice<EhrResource> second = queries.findPage(USER_ID, SOURCE, null, null, PageRequest.of(1, 2));

        // Assert
        assertThat(ids(first)).containsExactly("c-new", "c-mid");
        assertThat(first.hasNext()).isTrue();
        assertThat(ids(second)).containsExactly("o-old", "c-undated");
        assertThat(second.hasNext()).isFalse();
    }

    @Test
    @DisplayName("both bounds keep dates and timestamps inside the range and drop undated rows")
    void bothBounds() {
        // Act: from 2024-01-01 through 2024-06-01 inclusive, so the exclusive bound is the next day.
        final Slice<EhrResource> slice =
                queries.findPage(USER_ID, SOURCE, "2024-01-01", "2024-06-02", PageRequest.of(0, 20));

        // Assert
        assertThat(ids(slice)).containsExactly("c-new", "c-mid");
    }

    @Test
    @DisplayName("one bound with the other left null runs on PostgreSQL and applies only the given bound")
    void oneBoundAndOneNull() {
        // Act
        final Slice<EhrResource> fromOnly = queries.findPage(USER_ID, SOURCE, "2024-01-01", null, PageRequest.of(0, 20));
        final Slice<EhrResource> toOnly = queries.findPage(USER_ID, SOURCE, null, "2024-01-01", PageRequest.of(0, 20));

        // Assert
        assertThat(ids(fromOnly)).containsExactly("c-new", "c-mid");
        assertThat(ids(toOnly)).containsExactly("o-old");
    }

    @Test
    @DisplayName("records of one type are found for post-sync reconciliation")
    void findsOneTypeForReconciliation() {
        assertThat(queries.findByUserIdAndSourceAndResourceType(USER_ID, SOURCE, "Condition"))
                .extracting(EhrResource::getResourceFhirId)
                .containsExactlyInAnyOrder("c-new", "c-mid", "c-undated");
    }
}
