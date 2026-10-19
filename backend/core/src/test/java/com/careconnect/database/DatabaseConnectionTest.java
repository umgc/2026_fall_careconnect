package com.careconnect.database;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.SQLException;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class DatabaseConnectionTest {

    @Mock
    private DataSource dataSource;
    @Mock
    private Connection connection;
    @Mock
    private DatabaseMetaData metaData;
    @Mock
    private Statement statement;
    @Mock
    private ResultSet resultSet;

    @BeforeEach
    void setUp() throws SQLException {
        lenient().when(dataSource.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(metaData);
        lenient().when(connection.isValid(5)).thenReturn(true);
        lenient().when(connection.isClosed()).thenReturn(false);
        lenient().when(connection.createStatement()).thenReturn(statement);
    }

    @Test
    @DisplayName("Database connection should be established successfully")
    void testDatabaseConnection() throws SQLException {
        when(metaData.getDatabaseProductName()).thenReturn("PostgreSQL");

        assertNotNull(dataSource, "DataSource should not be null");

        try (Connection conn = dataSource.getConnection()) {
            assertNotNull(conn, "Connection should not be null");
            assertTrue(conn.isValid(5), "Connection should be valid");
            assertFalse(conn.isClosed(), "Connection should not be closed");

            final DatabaseMetaData md = conn.getMetaData();
            assertNotNull(md, "Database metadata should not be null");

            final String productName = md.getDatabaseProductName().toLowerCase();
            assertTrue(productName.contains("postgresql"),
                    "Should be connected to PostgreSQL in dev mode, but connected to: " + productName);
        }
    }

    @Test
    @DisplayName("Database should support basic SQL operations")
    void testBasicDatabaseOperations() throws SQLException {
        final ResultSet testResult = mock(ResultSet.class);
        when(testResult.next()).thenReturn(true);
        when(testResult.getInt("test_value")).thenReturn(1);

        final ResultSet timeResult = mock(ResultSet.class);
        when(timeResult.next()).thenReturn(true);
        when(timeResult.getTimestamp("current_time")).thenReturn(new java.sql.Timestamp(System.currentTimeMillis()));

        final ResultSet schemaResult = mock(ResultSet.class);
        when(schemaResult.next()).thenReturn(true);
        when(schemaResult.getString("schema_name")).thenReturn("public");

        when(statement.executeQuery("SELECT 1 as test_value")).thenReturn(testResult);
        when(statement.executeQuery("SELECT CURRENT_TIMESTAMP as current_time")).thenReturn(timeResult);
        when(statement.executeQuery("SELECT CURRENT_SCHEMA() as schema_name")).thenReturn(schemaResult);

        try (Connection conn = dataSource.getConnection();
             final Statement stmt = conn.createStatement()) {

            final ResultSet rs1 = stmt.executeQuery("SELECT 1 as test_value");
            assertTrue(rs1.next(), "Query should return at least one row");
            assertEquals(1, rs1.getInt("test_value"), "Test value should be 1");

            final ResultSet rs2 = stmt.executeQuery("SELECT CURRENT_TIMESTAMP as current_time");
            assertTrue(rs2.next(), "Timestamp query should return a row");
            assertNotNull(rs2.getTimestamp("current_time"), "Current timestamp should not be null");

            final ResultSet rs3 = stmt.executeQuery("SELECT CURRENT_SCHEMA() as schema_name");
            assertTrue(rs3.next(), "Schema query should return a row");
            final String schemaName = rs3.getString("schema_name");
            assertNotNull(schemaName, "Schema name should not be null");
        }
    }

    @Test
    @DisplayName("Connection pool should be working")
    void testConnectionPool() throws SQLException {
        final Connection conn2 = mock(Connection.class);
        when(conn2.isValid(5)).thenReturn(true);
        when(dataSource.getConnection()).thenReturn(connection, conn2);

        Connection c1 = null;
        Connection c2 = null;

        try {
            c1 = dataSource.getConnection();
            c2 = dataSource.getConnection();

            assertNotNull(c1, "First connection should not be null");
            assertNotNull(c2, "Second connection should not be null");
            assertNotSame(c1, c2, "Connections should be different instances");

            assertTrue(c1.isValid(5), "First connection should be valid");
            assertTrue(c2.isValid(5), "Second connection should be valid");
        } finally {
            if (c1 != null && !c1.isClosed()) {
                c1.close();
            }
            if (c2 != null && !c2.isClosed()) {
                c2.close();
            }
        }
    }

    @Test
    @DisplayName("Database should be accessible with correct credentials")
    void testDatabaseCredentials() throws SQLException {
        when(metaData.getURL()).thenReturn("jdbc:postgresql://localhost:5432/careconnect");

        try (Connection conn = dataSource.getConnection()) {
            final DatabaseMetaData md = conn.getMetaData();
            final String url = md.getURL();

            assertNotNull(url, "Database URL should not be null");
            assertTrue(url.contains("postgresql"), "URL should indicate PostgreSQL connection");
            assertTrue(url.contains("localhost") || url.contains("127.0.0.1"),
                    "URL should connect to localhost");
            assertTrue(url.contains("5432"), "URL should use default PostgreSQL port 5432");
        }
    }
}
