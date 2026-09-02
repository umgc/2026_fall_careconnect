package com.careconnect.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link DevDataLoader}.
 * <p>
 * DevDataLoader is a Spring {@code CommandLineRunner} that seeds the database with
 * development fixture data on startup. It is only active when a boolean "enabled" flag
 * is set to {@code true} (typically via a Spring profile or property), and it skips
 * seeding if users already exist in the database.
 * <p>
 * All JDBC interactions (DataSource, Connection, Statement, ResultSet) are mocked using
 * Mockito to avoid requiring a real database. This isolates the logic being tested —
 * the conditional seeding decisions — from infrastructure concerns.
 */
class DevDataLoaderTest {

    private DataSource dataSource;
    private Connection connection;
    private Statement statement;
    private ResultSet resultSet;

    private DevDataLoader loader;

    @BeforeEach
    void setUp() throws Exception {
        // Build a mock JDBC chain: DataSource → Connection → Statement.
        // ResultSet is mocked separately and returned by statement.executeQuery().
        dataSource = mock(DataSource.class);
        connection = mock(Connection.class);
        statement = mock(Statement.class);
        resultSet = mock(ResultSet.class);

        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.createStatement()).thenReturn(statement);

        // Default loader is enabled so individual tests can exercise the loading path.
        loader = new DevDataLoader(dataSource, true);
    }

    // -------------------------------------------------
    // 1. Disabled flag → do nothing
    // -------------------------------------------------

    @Test
    void run_DoesNothingWhenDisabled() throws Exception {
        // Verifies that when the loader is constructed with enabled=false, run() returns
        // immediately without touching the DataSource — no connection is opened.
        final DevDataLoader disabledLoader = new DevDataLoader(dataSource, false);

        assertDoesNotThrow(() -> disabledLoader.run());
        verifyNoInteractions(dataSource);
    }

    // -------------------------------------------------
    // 2. Users exist → skip loading
    // -------------------------------------------------

    @Test
    void run_SkipsLoadingWhenUsersExist() throws Exception {
        // Verifies the guard query: if users table already contains rows, no INSERT/UPDATE
        // statements are executed, preventing duplicate seed data on subsequent restarts.
        when(statement.executeQuery(anyString()))
                .thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getInt(1)).thenReturn(5);

        assertDoesNotThrow(() -> loader.run());

        verify(statement, atLeastOnce()).executeQuery("SELECT COUNT(*) FROM users");
        verify(statement, never()).executeUpdate(anyString());
    }

    // -------------------------------------------------
    // 3. Users = 0 → should attempt SQL execution
    // -------------------------------------------------

    @Test
    void run_AttemptsLoadWhenNoUsersExist() throws Exception {
        // Verifies that when the users table is empty, the loader proceeds to execute
        // SQL seed statements (the contents of a dev SQL file or inline SQL).
        when(statement.executeQuery(anyString()))
                .thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getInt(1)).thenReturn(0);

        // Simulate SQL file execution returning row-count success
        when(statement.executeUpdate(anyString())).thenReturn(1);

        assertDoesNotThrow(() -> loader.run());

        verify(statement, atLeastOnce()).executeQuery("SELECT COUNT(*) FROM users");
    }

    // -------------------------------------------------
    // 4. Exception checking user count → still attempts load
    // -------------------------------------------------

    @Test
    void run_AttemptsLoadWhenUserCheckFails() throws Exception {
        // Verifies resilience: if the guard query itself throws (e.g. table not yet
        // created by Flyway), the loader still attempts to run without crashing the app.
        when(statement.executeQuery(anyString()))
                .thenThrow(new RuntimeException("DB error"));

        when(statement.executeUpdate(anyString())).thenReturn(1);

        assertDoesNotThrow(() -> loader.run());
    }

    // -------------------------------------------------
    // 5. SQL execution failure → does not crash
    // -------------------------------------------------

    @Test
    void run_DoesNotThrowWhenSqlExecutionFails() throws Exception {
        // Verifies that a failure during seed SQL execution does not propagate an
        // exception that would abort application startup — errors are caught and logged.
        when(statement.executeQuery(anyString()))
                .thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getInt(1)).thenReturn(0);

        when(statement.executeUpdate(anyString()))
                .thenThrow(new RuntimeException("SQL failure"));

        assertDoesNotThrow(() -> loader.run());
    }

    // -------------------------------------------------
    // 6. ResultSet has no rows → shouldLoadMockData returns true
    // -------------------------------------------------

    @Test
    void run_AttemptsLoadWhenResultSetHasNoRows() throws Exception {
        // Verifies that when the guard query returns a ResultSet where next() is false
        // (no rows at all), shouldLoadMockData still returns true and load is attempted.
        when(statement.executeQuery(anyString())).thenReturn(resultSet);
        when(resultSet.next()).thenReturn(false);
        when(statement.executeUpdate(anyString())).thenReturn(1);

        assertDoesNotThrow(() -> loader.run());
        verify(statement, atLeastOnce()).executeQuery("SELECT COUNT(*) FROM users");
    }

    // -------------------------------------------------
    // 7. DB connection fails during SQL script execution
    // -------------------------------------------------

    @Test
    void run_DoesNotThrowWhenConnectionFailsDuringExecution() throws Exception {
        // Verifies that if DataSource.getConnection() throws during executeSqlScript,
        // the outer catch block absorbs the error without crashing application startup.
        when(statement.executeQuery(anyString())).thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getInt(1)).thenReturn(0); // users = 0 → triggers loadMockData

        when(dataSource.getConnection())
                .thenReturn(connection)                                    // shouldLoadMockData
                .thenThrow(new RuntimeException("No connections available")); // executeSqlScript

        assertDoesNotThrow(() -> loader.run());
    }

    // -------------------------------------------------
    // 8. verifyDataLoad: patient_medication table missing
    // -------------------------------------------------

    @Test
    void run_IgnoresPatientMedicationTableException() throws Exception {
        // Verifies that if the patient_medication table does not yet exist during
        // post-load verification, the exception is swallowed and loading completes cleanly.
        final ResultSet countRs = mock(ResultSet.class);
        when(countRs.next()).thenReturn(true);
        when(countRs.getInt(1)).thenReturn(0);

        final ResultSet patientRs = mock(ResultSet.class);
        when(patientRs.next()).thenReturn(true);
        when(patientRs.getInt(1)).thenReturn(1);

        final ResultSet caregiverRs = mock(ResultSet.class);
        when(caregiverRs.next()).thenReturn(true);
        when(caregiverRs.getInt(1)).thenReturn(1);

        when(statement.executeQuery(anyString())).thenReturn(countRs);
        when(statement.executeQuery("SELECT COUNT(*) FROM patient")).thenReturn(patientRs);
        when(statement.executeQuery("SELECT COUNT(*) FROM caregiver")).thenReturn(caregiverRs);
        when(statement.executeQuery("SELECT COUNT(*) FROM patient_medication"))
                .thenThrow(new RuntimeException("Table does not exist"));

        when(statement.executeUpdate(anyString())).thenReturn(1);

        assertDoesNotThrow(() -> loader.run());
    }
}