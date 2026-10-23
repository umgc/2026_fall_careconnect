package com.careconnect.service.ehr;

import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Control-flow tests for {@link EhrSourceDataPurger} with a mocked {@link EntityManager}: which
 * tables a purge touches and which it never does. {@code EhrSourceDataPurgerPostgresTest} proves the
 * deletes against a real database.
 */
class EhrSourceDataPurgerTest {

    private EntityManager entityManager;
    private Query query;
    private EhrSourceDataPurger purger;

    @BeforeEach
    void setUp() {
        entityManager = mock(EntityManager.class);
        query = mock(Query.class);
        when(entityManager.createQuery(anyString())).thenReturn(query);
        when(query.setParameter(anyString(), any())).thenReturn(query);
        when(query.executeUpdate()).thenReturn(2);
        purger = new EhrSourceDataPurger(entityManager);
    }

    @Test
    @DisplayName("purges the mirror and the four canonical tables, and never the audit log")
    void purgesEveryTableExceptTheAuditLog() {
        // Act
        final EhrSourceDataPurger.Purged purged = purger.purge(7L, 5L, 9L, "ATHENAHEALTH");

        // Assert
        assertEquals(new EhrSourceDataPurger.Purged(2, 2, 2, 2, 2), purged);
        final ArgumentCaptor<String> statements = ArgumentCaptor.forClass(String.class);
        verify(entityManager, times(5)).createQuery(statements.capture());
        final List<String> all = statements.getAllValues();
        assertEquals(List.of("EhrResource", "EhrRawPayload", "EhrSourceIdentity", "EhrIdentityConflict",
                "EhrPatientCrosswalk"), all.stream().map(s -> s.split(" ")[2]).toList());
        all.forEach(statement -> assertEquals(-1, statement.indexOf("EhrAuditEvent")));
    }

    @Test
    @DisplayName("without a canonical patient or source id only the user-keyed mirror is purged")
    void withoutCanonicalIdsOnlyTheMirrorGoes() {
        // Act
        final EhrSourceDataPurger.Purged purged = purger.purge(7L, null, 9L, "ATHENAHEALTH");

        // Assert
        assertEquals(new EhrSourceDataPurger.Purged(2, 0, 0, 0, 0), purged);
        verify(entityManager, times(1)).createQuery(anyString());
    }
}
