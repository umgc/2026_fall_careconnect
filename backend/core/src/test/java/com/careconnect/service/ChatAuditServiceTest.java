package com.careconnect.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.MockitoAnnotations;
import org.slf4j.Logger;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import org.mockito.MockedStatic;

/**
 * Unit tests for {@link ChatAuditService}.
 *
 * <p>Tests cover all public methods, all private helper branches
 * (null checks, truncation, IP anonymization, hashing, error
 * fallback), and the AuditLogEntry inner model.
 */
class ChatAuditServiceTest {

    private ChatAuditService service;
    private Logger mockLogger;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        service = new ChatAuditService();

        // Replace Lombok-generated log field with a mock so we
        // can verify logging output
        mockLogger = mock(Logger.class);
        Field logField =
                ChatAuditService.class.getDeclaredField("log");
        logField.setAccessible(true);

        // The log field is static final; handle both Java < 17
        // and Java 17+ runtimes.
        try {
            // Java < 17 approach
            java.lang.reflect.Field modifiersField =
                    Field.class.getDeclaredField("modifiers");
            modifiersField.setAccessible(true);
            modifiersField.setInt(logField,
                    logField.getModifiers()
                            & ~java.lang.reflect.Modifier.FINAL);
            logField.set(null, mockLogger);
        } catch (NoSuchFieldException e) {
            // Java 17+ approach using Unsafe
            var unsafeClass =
                    Class.forName("sun.misc.Unsafe");
            var unsafeField =
                    unsafeClass.getDeclaredField("theUnsafe");
            unsafeField.setAccessible(true);
            var unsafe = unsafeField.get(null);

            var staticFieldBase = unsafeClass.getMethod(
                    "staticFieldBase", Field.class);
            var staticFieldOffset = unsafeClass.getMethod(
                    "staticFieldOffset", Field.class);
            var putObject = unsafeClass.getMethod(
                    "putObject",
                    Object.class, long.class, Object.class);

            Object base =
                    staticFieldBase.invoke(unsafe, logField);
            long offset =
                    (long) staticFieldOffset.invoke(unsafe, logField);
            putObject.invoke(unsafe, base, offset, mockLogger);
        }
    }

    // ---- Helpers to invoke private methods via reflection ----

    private String invokeHashUserId(Long userId)
            throws Exception {
        Method m = ChatAuditService.class.getDeclaredMethod(
                "hashUserId", Long.class);
        m.setAccessible(true);
        return (String) m.invoke(service, userId);
    }

    private String invokeSanitizeUserAgent(String userAgent)
            throws Exception {
        Method m = ChatAuditService.class.getDeclaredMethod(
                "sanitizeUserAgent", String.class);
        m.setAccessible(true);
        return (String) m.invoke(service, userAgent);
    }

    private String invokeAnonymizeIpAddress(String ipAddress)
            throws Exception {
        Method m = ChatAuditService.class.getDeclaredMethod(
                "anonymizeIpAddress", String.class);
        m.setAccessible(true);
        return (String) m.invoke(service, ipAddress);
    }

    // ===========================================================
    //  hashUserId tests
    // ===========================================================
    @Nested
    @DisplayName("hashUserId tests")
    class HashUserIdTests {

        @Test
        @DisplayName("hashUserId - null userId - returns anonymous")
        void hashUserId_nullUserId_returnsAnonymous()
                throws Exception {
            String result = invokeHashUserId(null);
            assertEquals("anonymous", result);
        }

        @Test
        @DisplayName("hashUserId - valid userId - returns hashed "
                + "string starting with user_ prefix")
        void hashUserId_validUserId_returnsHashedString()
                throws Exception {
            String result = invokeHashUserId(42L);
            assertNotNull(result);
            assertTrue(result.startsWith("user_"));
            // "user_" (5) + 12 hash chars = 17 total
            assertEquals(17, result.length());
        }

        @Test
        @DisplayName("hashUserId - same userId twice - returns "
                + "deterministic result")
        void hashUserId_sameUserId_returnsDeterministicResult()
                throws Exception {
            String result1 = invokeHashUserId(123L);
            String result2 = invokeHashUserId(123L);
            assertEquals(result1, result2);
        }

        @Test
        @DisplayName("hashUserId - different userIds - returns "
                + "different hashes")
        void hashUserId_differentUserIds_returnsDifferentHashes()
                throws Exception {
            String result1 = invokeHashUserId(1L);
            String result2 = invokeHashUserId(2L);
            assertNotEquals(result1, result2);
        }

        @Test
        @DisplayName("hashUserId - MessageDigest exception - "
                + "returns fallback UUID-based string and logs error")
        void hashUserId_digestException_returnsFallbackAndLogsError()
                throws Exception {
            try (MockedStatic<MessageDigest> mdMock =
                         mockStatic(MessageDigest.class)) {
                mdMock.when(() -> MessageDigest.getInstance("SHA-256"))
                        .thenThrow(
                                new NoSuchAlgorithmException("mocked failure"));

                String result = invokeHashUserId(99L);

                assertNotNull(result);
                assertTrue(result.startsWith("user_"));
                // "user_" (5) + 8 UUID chars = 13 total
                assertEquals(13, result.length());

                verify(mockLogger).error(
                        eq("Error hashing user ID: {}"),
                        eq("mocked failure"));
            }
        }

        @Test
        @DisplayName("hashUserId - zero userId - returns valid "
                + "hashed string")
        void hashUserId_zeroUserId_returnsHashedString()
                throws Exception {
            String result = invokeHashUserId(0L);
            assertNotNull(result);
            assertTrue(result.startsWith("user_"));
            assertEquals(17, result.length());
        }

        @Test
        @DisplayName("hashUserId - negative userId - returns "
                + "valid hashed string")
        void hashUserId_negativeUserId_returnsHashedString()
                throws Exception {
            String result = invokeHashUserId(-1L);
            assertNotNull(result);
            assertTrue(result.startsWith("user_"));
            assertEquals(17, result.length());
        }

        @Test
        @DisplayName("hashUserId - large userId - returns valid "
                + "hashed string")
        void hashUserId_largeUserId_returnsHashedString()
                throws Exception {
            String result = invokeHashUserId(Long.MAX_VALUE);
            assertNotNull(result);
            assertTrue(result.startsWith("user_"));
            assertEquals(17, result.length());
        }
    }

    // ===========================================================
    //  sanitizeUserAgent tests
    // ===========================================================
    @Nested
    @DisplayName("sanitizeUserAgent tests")
    class SanitizeUserAgentTests {

        @Test
        @DisplayName("sanitizeUserAgent - null input - returns "
                + "unknown")
        void sanitizeUserAgent_nullInput_returnsUnknown()
                throws Exception {
            assertEquals("unknown", invokeSanitizeUserAgent(null));
        }

        @Test
        @DisplayName("sanitizeUserAgent - short string - returns "
                + "string unchanged")
        void sanitizeUserAgent_shortString_returnsUnchanged()
                throws Exception {
            String ua = "Mozilla/5.0 (Windows NT 10.0)";
            assertEquals(ua, invokeSanitizeUserAgent(ua));
        }

        @Test
        @DisplayName("sanitizeUserAgent - exactly 100 chars - "
                + "returns string unchanged")
        void sanitizeUserAgent_exactly100Chars_returnsUnchanged()
                throws Exception {
            String ua = "A".repeat(100);
            assertEquals(ua, invokeSanitizeUserAgent(ua));
        }

        @Test
        @DisplayName("sanitizeUserAgent - over 100 chars - "
                + "returns truncated to 100")
        void sanitizeUserAgent_over100Chars_returnsTruncated()
                throws Exception {
            String ua = "B".repeat(150);
            String result = invokeSanitizeUserAgent(ua);
            assertEquals(100, result.length());
            assertEquals("B".repeat(100), result);
        }

        @Test
        @DisplayName("sanitizeUserAgent - 101 chars - returns "
                + "truncated to 100")
        void sanitizeUserAgent_101Chars_returnsTruncated()
                throws Exception {
            String ua = "C".repeat(101);
            String result = invokeSanitizeUserAgent(ua);
            assertEquals(100, result.length());
        }

        @Test
        @DisplayName("sanitizeUserAgent - empty string - returns "
                + "empty string")
        void sanitizeUserAgent_emptyString_returnsEmpty()
                throws Exception {
            assertEquals("", invokeSanitizeUserAgent(""));
        }
    }

    // ===========================================================
    //  anonymizeIpAddress tests
    // ===========================================================
    @Nested
    @DisplayName("anonymizeIpAddress tests")
    class AnonymizeIpAddressTests {

        @Test
        @DisplayName("anonymizeIpAddress - null input - returns "
                + "unknown")
        void anonymizeIpAddress_nullInput_returnsUnknown()
                throws Exception {
            assertEquals("unknown",
                    invokeAnonymizeIpAddress(null));
        }

        @Test
        @DisplayName("anonymizeIpAddress - valid IPv4 - replaces "
                + "last octet with xxx")
        void anonymizeIpAddress_validIpv4_replacesLastOctet()
                throws Exception {
            String result =
                    invokeAnonymizeIpAddress("192.168.1.100");
            assertEquals("192.168.1.xxx", result);
        }

        @Test
        @DisplayName("anonymizeIpAddress - IPv4 different values - "
                + "anonymizes correctly")
        void anonymizeIpAddress_ipv4DifferentValues_anonymizes()
                throws Exception {
            assertEquals("10.0.0.xxx",
                    invokeAnonymizeIpAddress("10.0.0.255"));
        }

        @Test
        @DisplayName("anonymizeIpAddress - dotted string with "
                + "fewer than 4 parts - returns anonymized")
        void anonymizeIpAddress_fewerThan4Parts_returnsAnonymized()
                throws Exception {
            // Contains dots but only 3 parts
            assertEquals("anonymized",
                    invokeAnonymizeIpAddress("192.168.1"));
        }

        @Test
        @DisplayName("anonymizeIpAddress - dotted string with "
                + "more than 4 parts - returns anonymized")
        void anonymizeIpAddress_moreThan4Parts_returnsAnonymized()
                throws Exception {
            assertEquals("anonymized",
                    invokeAnonymizeIpAddress("1.2.3.4.5"));
        }

        @Test
        @DisplayName("anonymizeIpAddress - IPv6 without dots - "
                + "returns anonymized")
        void anonymizeIpAddress_ipv6NoDots_returnsAnonymized()
                throws Exception {
            assertEquals("anonymized",
                    invokeAnonymizeIpAddress("::1"));
        }

        @Test
        @DisplayName("anonymizeIpAddress - no dots at all - "
                + "returns anonymized")
        void anonymizeIpAddress_noDots_returnsAnonymized()
                throws Exception {
            assertEquals("anonymized",
                    invokeAnonymizeIpAddress("localhost"));
        }

        @Test
        @DisplayName("anonymizeIpAddress - empty string - returns "
                + "anonymized")
        void anonymizeIpAddress_emptyString_returnsAnonymized()
                throws Exception {
            assertEquals("anonymized",
                    invokeAnonymizeIpAddress(""));
        }

        @Test
        @DisplayName("anonymizeIpAddress - single dot - returns "
                + "anonymized")
        void anonymizeIpAddress_singleDot_returnsAnonymized()
                throws Exception {
            // Contains dot but only 2 parts
            assertEquals("anonymized",
                    invokeAnonymizeIpAddress("192.168"));
        }

        @Test
        @DisplayName("anonymizeIpAddress - loopback IPv4 - "
                + "anonymizes correctly")
        void anonymizeIpAddress_loopbackIpv4_anonymizes()
                throws Exception {
            assertEquals("127.0.0.xxx",
                    invokeAnonymizeIpAddress("127.0.0.1"));
        }
    }

    // ===========================================================
    //  logChatSessionStart tests
    // ===========================================================
    @Nested
    @DisplayName("logChatSessionStart tests")
    class LogChatSessionStartTests {

        @Test
        @DisplayName("logChatSessionStart - valid inputs - logs "
                + "audit entry with correct action and metadata")
        void logChatSessionStart_validInputs_logsAuditEntry() throws Exception {
            service.logChatSessionStart(
                    1L, "session-123", "TestBrowser/1.0", "10.0.0.1");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    argThat(s -> s.toString().startsWith("user_")),
                    eq("session-123"),
                    eq("CHAT_SESSION_STARTED"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return "TestBrowser/1.0".equals(
                                map.get("user_agent"))
                                && "10.0.0.xxx".equals(
                                map.get("ip_address"))
                                && "ai_chat".equals(
                                map.get("session_type"));
                    }));
        }

        @Test
        @DisplayName("logChatSessionStart - null userId - logs "
                + "with anonymous user")
        void logChatSessionStart_nullUserId_logsAnonymous() throws Exception {
            service.logChatSessionStart(
                    null, "session-456", "Agent/2.0", "192.168.1.1");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    eq("anonymous"),
                    eq("session-456"),
                    eq("CHAT_SESSION_STARTED"),
                    any());
        }

        @Test
        @DisplayName("logChatSessionStart - null userAgent and "
                + "null IP - handles gracefully")
        void logChatSessionStart_nullUserAgentAndIp_handlesGracefully() throws Exception {
            service.logChatSessionStart(
                    1L, "session-789", null, null);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    any(),
                    eq("session-789"),
                    eq("CHAT_SESSION_STARTED"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return "unknown".equals(map.get("user_agent"))
                                && "unknown".equals(map.get("ip_address"));
                    }));
        }

        @Test
        @DisplayName("logChatSessionStart - long userAgent - "
                + "truncates to 100 chars")
        void logChatSessionStart_longUserAgent_truncates() throws Exception {
            String longUa = "X".repeat(200);
            service.logChatSessionStart(
                    1L, "session-trunc", longUa, "1.2.3.4");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(), any(), any(), any(),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        String ua = (String) map.get("user_agent");
                        return ua.length() == 100;
                    }));
        }

        @Test
        @DisplayName("logChatSessionStart - non-IPv4 address - "
                + "anonymizes to anonymized string")
        void logChatSessionStart_nonIpv4_anonymizes() throws Exception {
            service.logChatSessionStart(
                    1L, "session-ipv6", "Browser/1.0",
                    "fe80::1%lo0");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(), any(), any(), any(),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return "anonymized".equals(
                                map.get("ip_address"));
                    }));
        }
    }

    // ===========================================================
    //  logMessageSent tests
    // ===========================================================
    @Nested
    @DisplayName("logMessageSent tests")
    class LogMessageSentTests {

        @Test
        @DisplayName("logMessageSent - valid inputs - logs "
                + "MESSAGE_SENT action with metadata")
        void logMessageSent_validInputs_logsMessageSent() throws Exception {
            service.logMessageSent(5L, "sess-1", 256, 150L);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    argThat(s -> s.toString().startsWith("user_")),
                    eq("sess-1"),
                    eq("MESSAGE_SENT"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return Integer.valueOf(256).equals(
                                map.get("message_length"))
                                && Long.valueOf(150L).equals(
                                map.get("response_time_ms"))
                                && "user_to_ai".equals(
                                map.get("message_type"));
                    }));
        }

        @Test
        @DisplayName("logMessageSent - null userId - logs with "
                + "anonymous user")
        void logMessageSent_nullUserId_logsAnonymous() throws Exception {
            service.logMessageSent(null, "sess-2", 100, 50L);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    eq("anonymous"),
                    eq("sess-2"),
                    eq("MESSAGE_SENT"),
                    any());
        }

        @Test
        @DisplayName("logMessageSent - zero length and time - "
                + "logs valid entry")
        void logMessageSent_zeroValues_logsValidEntry() throws Exception {
            service.logMessageSent(1L, "sess-zero", 0, 0L);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(), any(),
                    eq("sess-zero"),
                    eq("MESSAGE_SENT"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return Integer.valueOf(0).equals(
                                map.get("message_length"))
                                && Long.valueOf(0L).equals(
                                map.get("response_time_ms"));
                    }));
        }
    }

    // ===========================================================
    //  logAiResponse tests
    // ===========================================================
    @Nested
    @DisplayName("logAiResponse tests")
    class LogAiResponseTests {

        @Test
        @DisplayName("logAiResponse - valid inputs - logs "
                + "AI_RESPONSE_GENERATED action")
        void logAiResponse_validInputs_logsAiResponseGenerated() throws Exception {
            service.logAiResponse(10L, "sess-ai", 512, 300L);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    argThat(s -> s.toString().startsWith("user_")),
                    eq("sess-ai"),
                    eq("AI_RESPONSE_GENERATED"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return Integer.valueOf(512).equals(
                                map.get("response_length"))
                                && Long.valueOf(300L).equals(
                                map.get("processing_time_ms"))
                                && "ai_to_user".equals(
                                map.get("response_type"));
                    }));
        }

        @Test
        @DisplayName("logAiResponse - null userId - logs with "
                + "anonymous user")
        void logAiResponse_nullUserId_logsAnonymous() throws Exception {
            service.logAiResponse(null, "sess-ai2", 100, 50L);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    eq("anonymous"),
                    any(),
                    eq("AI_RESPONSE_GENERATED"),
                    any());
        }
    }

    // ===========================================================
    //  logConversationDeleted tests
    // ===========================================================
    @Nested
    @DisplayName("logConversationDeleted tests")
    class LogConversationDeletedTests {

        @Test
        @DisplayName("logConversationDeleted - valid inputs - "
                + "logs CONVERSATION_DELETED action")
        void logConversationDeleted_validInputs_logs() throws Exception {
            service.logConversationDeleted(
                    7L, "sess-del", "user_requested");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    argThat(s -> s.toString().startsWith("user_")),
                    eq("sess-del"),
                    eq("CONVERSATION_DELETED"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return "user_requested".equals(
                                map.get("deletion_reason"))
                                && "user_initiated".equals(
                                map.get("deletion_type"));
                    }));
        }

        @Test
        @DisplayName("logConversationDeleted - null userId - "
                + "logs with anonymous user")
        void logConversationDeleted_nullUserId_logsAnonymous() throws Exception {
            service.logConversationDeleted(
                    null, "sess-del2", "privacy");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    eq("anonymous"),
                    any(),
                    eq("CONVERSATION_DELETED"),
                    any());
        }
    }

    // ===========================================================
    //  logConversationShared tests
    // ===========================================================
    @Nested
    @DisplayName("logConversationShared tests")
    class LogConversationSharedTests {

        @Test
        @DisplayName("logConversationShared - valid inputs - "
                + "logs CONVERSATION_SHARED with hashed provider")
        void logConversationShared_validInputs_logs() throws Exception {
            service.logConversationShared(
                    3L, "sess-share", 50L);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    argThat(s -> s.toString().startsWith("user_")),
                    eq("sess-share"),
                    eq("CONVERSATION_SHARED"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        String providerId =
                                (String) map.get("provider_id");
                        return providerId != null
                                && providerId.startsWith("user_")
                                && "user_consent".equals(
                                map.get("share_type"));
                    }));
        }

        @Test
        @DisplayName("logConversationShared - null providerId - "
                + "logs anonymous provider")
        void logConversationShared_nullProviderId_logsAnonymous() throws Exception {
            service.logConversationShared(
                    1L, "sess-share2", null);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(), any(), any(),
                    eq("CONVERSATION_SHARED"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return "anonymous".equals(
                                map.get("provider_id"));
                    }));
        }

        @Test
        @DisplayName("logConversationShared - null userId and "
                + "null providerId - both anonymous")
        void logConversationShared_bothNull_bothAnonymous() throws Exception {
            service.logConversationShared(
                    null, "sess-share3", null);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    eq("anonymous"),
                    eq("sess-share3"),
                    eq("CONVERSATION_SHARED"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return "anonymous".equals(
                                map.get("provider_id"));
                    }));
        }
    }

    // ===========================================================
    //  logSessionTimeout tests
    // ===========================================================
    @Nested
    @DisplayName("logSessionTimeout tests")
    class LogSessionTimeoutTests {

        @Test
        @DisplayName("logSessionTimeout - valid inputs - logs "
                + "SESSION_TIMEOUT action")
        void logSessionTimeout_validInputs_logsSessionTimeout() throws Exception {
            service.logSessionTimeout(20L, "sess-to", 30);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    argThat(s -> s.toString().startsWith("user_")),
                    eq("sess-to"),
                    eq("SESSION_TIMEOUT"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return Integer.valueOf(30).equals(
                                map.get("session_duration_minutes"))
                                && "inactivity".equals(
                                map.get("timeout_reason"));
                    }));
        }

        @Test
        @DisplayName("logSessionTimeout - null userId - logs "
                + "with anonymous user")
        void logSessionTimeout_nullUserId_logsAnonymous() throws Exception {
            service.logSessionTimeout(null, "sess-to2", 15);

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    eq("anonymous"),
                    any(),
                    eq("SESSION_TIMEOUT"),
                    any());
        }
    }

    // ===========================================================
    //  logSystemError tests
    // ===========================================================
    @Nested
    @DisplayName("logSystemError tests")
    class LogSystemErrorTests {

        @Test
        @DisplayName("logSystemError - valid inputs - logs "
                + "SYSTEM_ERROR action with error details")
        void logSystemError_validInputs_logsSystemError() throws Exception {
            service.logSystemError(
                    15L, "sess-err", "ERR_500",
                    "InternalServerError");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    argThat(s -> s.toString().startsWith("user_")),
                    eq("sess-err"),
                    eq("SYSTEM_ERROR"),
                    argThat(m -> {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) m;
                        return "ERR_500".equals(
                                map.get("error_code"))
                                && "InternalServerError".equals(
                                map.get("error_type"))
                                && "error".equals(
                                map.get("severity"));
                    }));
        }

        @Test
        @DisplayName("logSystemError - null userId - logs with "
                + "anonymous user")
        void logSystemError_nullUserId_logsAnonymous() throws Exception {
            service.logSystemError(
                    null, "sess-err2", "ERR_401", "Unauthorized");

            verify(mockLogger).info(
                    eq("AUDIT: {} | User: {} | Session: {} "
                            + "| Action: {} | Metadata: {}"),
                    any(),
                    eq("anonymous"),
                    any(),
                    eq("SYSTEM_ERROR"),
                    any());
        }
    }

    // ===========================================================
    //  AuditLogEntry model tests
    // ===========================================================
    @Nested
    @DisplayName("AuditLogEntry tests")
    class AuditLogEntryTests {

        @Test
        @DisplayName("AuditLogEntry builder - creates entry with "
                + "all fields populated")
        void auditLogEntry_builder_createsWithAllFields() throws Exception {
            LocalDateTime now = LocalDateTime.now();
            Map<String, Object> meta = Map.of("key", "value");

            ChatAuditService.AuditLogEntry entry =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("log-1")
                            .timestamp(now)
                            .userId("user_abc")
                            .sessionId("sess-1")
                            .action("TEST_ACTION")
                            .metadata(meta)
                            .build();

            assertEquals("log-1", entry.getLogId());
            assertEquals(now, entry.getTimestamp());
            assertEquals("user_abc", entry.getUserId());
            assertEquals("sess-1", entry.getSessionId());
            assertEquals("TEST_ACTION", entry.getAction());
            assertEquals(meta, entry.getMetadata());
        }

        @Test
        @DisplayName("AuditLogEntry builder - creates entry with "
                + "null fields when not set")
        void auditLogEntry_builder_nullFieldsWhenNotSet() throws Exception {
            ChatAuditService.AuditLogEntry entry =
                    ChatAuditService.AuditLogEntry.builder().build();

            assertNull(entry.getLogId());
            assertNull(entry.getTimestamp());
            assertNull(entry.getUserId());
            assertNull(entry.getSessionId());
            assertNull(entry.getAction());
            assertNull(entry.getMetadata());
        }

        @Test
        @DisplayName("AuditLogEntry setters - modifies fields "
                + "via setters")
        void auditLogEntry_setters_modifiesFields() throws Exception {
            ChatAuditService.AuditLogEntry entry =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("initial")
                            .build();

            LocalDateTime fixedTime =
                    LocalDateTime.of(2024, 1, 1, 0, 0);

            entry.setLogId("updated");
            entry.setAction("NEW_ACTION");
            entry.setSessionId("new-session");
            entry.setUserId("new-user");
            entry.setTimestamp(fixedTime);
            entry.setMetadata(Map.of("new", "data"));

            assertEquals("updated", entry.getLogId());
            assertEquals("NEW_ACTION", entry.getAction());
            assertEquals("new-session", entry.getSessionId());
            assertEquals("new-user", entry.getUserId());
            assertEquals(fixedTime, entry.getTimestamp());
            assertEquals(Map.of("new", "data"),
                    entry.getMetadata());
        }

        @Test
        @DisplayName("AuditLogEntry equals - equal objects "
                + "return true")
        void auditLogEntry_equals_equalObjectsReturnTrue() throws Exception {
            LocalDateTime now =
                    LocalDateTime.of(2024, 6, 15, 12, 0);

            ChatAuditService.AuditLogEntry entry1 =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .timestamp(now)
                            .userId("user_x")
                            .sessionId("sess")
                            .action("ACT")
                            .metadata(Map.of())
                            .build();

            ChatAuditService.AuditLogEntry entry2 =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .timestamp(now)
                            .userId("user_x")
                            .sessionId("sess")
                            .action("ACT")
                            .metadata(Map.of())
                            .build();

            assertEquals(entry1, entry2);
        }

        @Test
        @DisplayName("AuditLogEntry hashCode - equal objects "
                + "have same hashCode")
        void auditLogEntry_hashCode_equalObjectsSameHash() throws Exception {
            LocalDateTime now =
                    LocalDateTime.of(2024, 6, 15, 12, 0);

            ChatAuditService.AuditLogEntry entry1 =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .timestamp(now)
                            .userId("user_x")
                            .sessionId("sess")
                            .action("ACT")
                            .metadata(Map.of())
                            .build();

            ChatAuditService.AuditLogEntry entry2 =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .timestamp(now)
                            .userId("user_x")
                            .sessionId("sess")
                            .action("ACT")
                            .metadata(Map.of())
                            .build();

            assertEquals(entry1.hashCode(), entry2.hashCode());
        }

        @Test
        @DisplayName("AuditLogEntry equals - different objects "
                + "return false")
        void auditLogEntry_equals_differentObjectsReturnFalse() throws Exception {
            ChatAuditService.AuditLogEntry entry1 =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .action("ACT_A")
                            .build();

            ChatAuditService.AuditLogEntry entry2 =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-2")
                            .action("ACT_B")
                            .build();

            assertNotEquals(entry1, entry2);
        }

        @Test
        @DisplayName("AuditLogEntry equals - compared to null - "
                + "returns false")
        void auditLogEntry_equals_comparedToNull_returnsFalse() throws Exception {
            ChatAuditService.AuditLogEntry entry =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .build();

            assertNotEquals(null, entry);
        }

        @Test
        @DisplayName("AuditLogEntry equals - same instance - "
                + "returns true")
        void auditLogEntry_equals_sameInstance_returnsTrue() throws Exception {
            ChatAuditService.AuditLogEntry entry =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .build();

            assertEquals(entry, entry);
        }

        @Test
        @DisplayName("AuditLogEntry toString - returns non-null "
                + "string containing field values")
        void auditLogEntry_toString_returnsNonNull() throws Exception {
            ChatAuditService.AuditLogEntry entry =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-toString")
                            .action("TO_STRING")
                            .build();

            String str = entry.toString();
            assertNotNull(str);
            assertTrue(str.contains("id-toString"));
            assertTrue(str.contains("TO_STRING"));
        }

        @Test
        @DisplayName("AuditLogEntry canEqual - same type returns "
                + "true")
        void auditLogEntry_canEqual_sameTypeReturnsTrue() throws Exception {
            ChatAuditService.AuditLogEntry entry1 =
                    ChatAuditService.AuditLogEntry.builder().build();
            ChatAuditService.AuditLogEntry entry2 =
                    ChatAuditService.AuditLogEntry.builder().build();

            assertTrue(entry1.canEqual(entry2));
        }

        @Test
        @DisplayName("AuditLogEntry equals - compared to "
                + "different type - returns false")
        void auditLogEntry_equals_differentType_returnsFalse() throws Exception {
            ChatAuditService.AuditLogEntry entry =
                    ChatAuditService.AuditLogEntry.builder()
                            .logId("id-1")
                            .build();

            assertNotEquals("not-an-entry", entry);
        }
    }
}
