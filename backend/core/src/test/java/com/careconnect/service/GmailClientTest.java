package com.careconnect.service;

import com.careconnect.dto.GmailDigestPayload;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class GmailClientTest {

    private static final String TOKEN = "test-token";
    // 2024-12-24 00:00:00 UTC in epoch millis
    private static final long RECENT_DATE_MS = 1735000000000L;
    private final ObjectMapper mapper = new ObjectMapper();
    @Mock
    private RestTemplate restTemplate;
    private GmailClient client;

    @BeforeEach
    void setUp() throws Exception {
        client = new GmailClient();
        ReflectionTestUtils.setField(client, "restTemplate", restTemplate);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    /**
     * Encode a string as Base64-URL so it can be used as Gmail message body.data
     */
    private String b64(String text) {
        return Base64.getUrlEncoder().encodeToString(text.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Parse a JSON string into a JsonNode
     */
    private JsonNode json(String raw) throws Exception {
        return mapper.readTree(raw);
    }

    /**
     * Build a minimal Gmail message JSON with an HTML part.
     * internalDate is set so resolveReceivedAt uses the epoch path.
     */
    private JsonNode htmlMessage(long internalDate, String htmlContent) throws Exception {
        final String data = b64(htmlContent);
        return json("{\"internalDate\":" + internalDate + ","
                + "\"payload\":{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + data + "\"},\"parts\":[]}}");
    }

    /**
     * Build a search-result JSON listing the given message IDs
     */
    private JsonNode searchResult(String... ids) throws Exception {
        final StringBuilder sb = new StringBuilder("{\"messages\":[");
        for (int i = 0; i < ids.length; i++) {
            if (i > 0) sb.append(',');
            sb.append("{\"id\":\"").append(ids[i]).append("\"}");
        }
        sb.append("]}");
        return json(sb.toString());
    }

    // ═════════════════════════════════════════════════════════════════════════
    // fetchDigestForDate
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void fetchDigestForDate_exchangeThrows_returnsEmpty() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenThrow(new RuntimeException("network error"));

        assertThat(client.fetchDigestForDate(TOKEN, LocalDate.of(2025, 10, 27))).isEmpty();
    }

    @Test
    void fetchDigestForDate_nullResponseBody_returnsEmpty() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok((JsonNode) null));

        assertThat(client.fetchDigestForDate(TOKEN, LocalDate.of(2025, 10, 27))).isEmpty();
    }

    @Test
    void fetchDigestForDate_noMessagesField_returnsEmpty() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(json("{}")));

        assertThat(client.fetchDigestForDate(TOKEN, LocalDate.of(2025, 10, 27))).isEmpty();
    }

    @Test
    void fetchDigestForDate_messageRefMissingId_skipped() throws Exception {
        // Message ref has no "id" field → asText(null) returns null → continue
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(json("{\"messages\":[{}]}")));

        assertThat(client.fetchDigestForDate(TOKEN, LocalDate.of(2025, 10, 27))).isEmpty();
    }

    @Test
    void fetchDigestForDate_messageBodyNull_skipped() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok((JsonNode) null));

        assertThat(client.fetchDigestForDate(TOKEN, LocalDate.of(2025, 10, 27))).isEmpty();
    }

    @Test
    void fetchDigestForDate_internalDateZero_skipped() throws Exception {
        // internalDate absent → asLong(0) = 0 → continue
        final JsonNode message = json("{\"payload\":{\"mimeType\":\"text/plain\","
                + "\"headers\":[],\"body\":{},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        assertThat(client.fetchDigestForDate(TOKEN, LocalDate.of(2025, 10, 27))).isEmpty();
    }

    @Test
    void fetchDigestForDate_messageDateDifferentFromTarget_noMatch() throws Exception {
        final LocalDate target = LocalDate.of(2025, 10, 27);
        // Use Oct 26 – different date from target
        final long oct26Ms = target.minusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli();
        final JsonNode message = json("{\"internalDate\":" + oct26Ms + ","
                + "\"payload\":{\"mimeType\":\"text/plain\",\"headers\":[],\"body\":{},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        assertThat(client.fetchDigestForDate(TOKEN, target)).isEmpty();
    }

    @Test
    void fetchDigestForDate_buildPayloadReturnsNull_skipped() throws Exception {
        final LocalDate target = LocalDate.of(2025, 10, 27);
        final long midnightMs = target.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli();
        // Matching date, but no HTML in payload → buildPayload returns null
        final JsonNode message = json("{\"internalDate\":" + midnightMs + ","
                + "\"payload\":{\"mimeType\":\"text/plain\",\"headers\":[],\"body\":{},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        assertThat(client.fetchDigestForDate(TOKEN, target)).isEmpty();
    }

    @Test
    void fetchDigestForDate_happyPath_returnsPayload() throws Exception {
        final LocalDate target = LocalDate.of(2025, 10, 27);
        final long midnightMs = target.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli();
        final JsonNode message = htmlMessage(midnightMs, "<html><body>Digest</body></html>");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchDigestForDate(TOKEN, target);
        assertThat(result).isPresent();
        assertThat(result.get().htmlBody()).contains("<html>");
    }

    @Test
    void fetchDigestForDate_twoMatchingMessages_closerToMidnightWins() throws Exception {
        final LocalDate target = LocalDate.of(2025, 10, 27);
        final long midnight = target.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli();
        final long earlyMs = midnight + 1_000L;           // 1 second after midnight – dateDiff = 1000
        final long laterMs = midnight + 3_600_000L;       // 1 hour after midnight  – dateDiff = 3,600,000

        final JsonNode msg1 = htmlMessage(earlyMs, "<html><body>Early</body></html>");
        final JsonNode msg2 = htmlMessage(laterMs, "<html><body>Late</body></html>");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1", "msg2")))
                .thenReturn(ResponseEntity.ok(msg1))
                .thenReturn(ResponseEntity.ok(msg2));

        final Optional<GmailDigestPayload> result = client.fetchDigestForDate(TOKEN, target);
        assertThat(result).isPresent();
        assertThat(result.get().htmlBody()).contains("Early");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // fetchLatestDigest
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void fetchLatestDigest_exchangeThrows_returnsEmpty() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenThrow(new RuntimeException("network error"));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void fetchLatestDigest_nullResponseBody_returnsEmpty() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok((JsonNode) null));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void fetchLatestDigest_noMessagesField_returnsEmpty() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(json("{}")));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void fetchLatestDigest_messageRefMissingId_skipped() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(json("{\"messages\":[{}]}")));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void fetchLatestDigest_messageBodyNull_skipped() throws Exception {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok((JsonNode) null));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void fetchLatestDigest_buildPayloadNull_skipped() throws Exception {
        // No HTML → buildPayload returns null → skip
        final JsonNode message = json("{\"internalDate\":1000,"
                + "\"payload\":{\"mimeType\":\"text/plain\",\"headers\":[],\"body\":{},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void fetchLatestDigest_happyPath_returnsPayload() throws Exception {
        final JsonNode message = htmlMessage(RECENT_DATE_MS, "<html><body>Latest</body></html>");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().htmlBody()).contains("Latest");
    }

    @Test
    void fetchLatestDigest_twoMessages_newestWins() throws Exception {
        final JsonNode msg1 = htmlMessage(1_000_000_000L, "<html><body>Older</body></html>");
        final JsonNode msg2 = htmlMessage(2_000_000_000L, "<html><body>Newer</body></html>");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1", "msg2")))
                .thenReturn(ResponseEntity.ok(msg1))
                .thenReturn(ResponseEntity.ok(msg2));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().htmlBody()).contains("Newer");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // resolveReceivedAt – internalDate == 0 path (returns now())
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void resolveReceivedAt_missingInternalDate_fallsBackToNow() throws Exception {
        // Message has no internalDate → asLong(0) = 0 → resolveReceivedAt returns now()
        // In fetchLatestDigest, 0 > -1 (newestDate initial) is still true, so result is present
        final JsonNode message = json("{\"payload\":{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + b64("<html><body>x</body></html>") + "\"},"
                + "\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().receivedAt()).isNotNull();
    }

    // ═════════════════════════════════════════════════════════════════════════
    // extractHtml branches
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void extractHtml_missingPayload_buildPayloadReturnsNull() throws Exception {
        // Message has no "payload" key → part.isMissingNode() = true → extractHtml returns null
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + "}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void extractHtml_htmlIsBlank_buildPayloadReturnsNull() throws Exception {
        // body.data decodes to whitespace → html.isBlank() → buildPayload returns null
        final String blankData = b64("   ");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + blankData + "\"},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void extractHtml_multipartBodyContainsHtml_usedDirectly() throws Exception {
        // mimeType starts with "multipart/", body.data decodes to HTML
        final String data = b64("<html><body>Multipart inline</body></html>");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/mixed\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + data + "\"},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().htmlBody()).containsIgnoringCase("<html");
    }

    @Test
    void extractHtml_multipartBodyNoHtmlTag_notUsed() throws Exception {
        // mimeType starts with "multipart/", body.data decodes to plain text (no <html tag)
        // Falls through to empty parts list → returns null → buildPayload null
        final String data = b64("plain text only, no html");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/mixed\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + data + "\"},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        assertThat(client.fetchLatestDigest(TOKEN)).isEmpty();
    }

    @Test
    void extractHtml_htmlFoundInChildPart() throws Exception {
        // Parent: multipart/alternative, no body data; child: text/html with data
        final String childData = b64("<html><body>Child HTML</body></html>");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/alternative\",\"headers\":[],"
                + "\"body\":{},\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + childData + "\"},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().htmlBody()).contains("Child HTML");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // collectInlinePart branches
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void collectInlinePart_noRecognisedCidHeader_skipped() throws Exception {
        // Part has headers but none are Content-ID / X-Attachment-Id / Content-Location
        final String data = b64("<html><body>test</body></html>");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"text/html\","
                + "\"headers\":[{\"name\":\"Content-Type\",\"value\":\"text/html\"}],"
                + "\"body\":{\"data\":\"" + data + "\"},\"parts\":[]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).isEmpty();
    }

    @Test
    void collectInlinePart_contentIdHeader_addsDataUrlToMap() throws Exception {
        final String htmlData = b64("<html><body>test</body></html>");
        // Tiny 3-byte payload for the inline image
        final String imgData = Base64.getUrlEncoder().encodeToString(new byte[]{(byte) 0xFF, (byte) 0xD8, 0x00});
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/jpeg\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<img001>\"}],"
                + "\"body\":{\"data\":\"" + imgData + "\"},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).containsKey("img001");
        assertThat(result.get().inlineCidData().get("img001")).startsWith("data:image/jpeg;base64,");
    }

    @Test
    void collectInlinePart_xAttachmentIdHeader_usedWhenNoContentId() throws Exception {
        final String htmlData = b64("<html><body>test</body></html>");
        final String imgData = Base64.getUrlEncoder().encodeToString(new byte[]{1, 2, 3});
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/png\","
                + "\"headers\":[{\"name\":\"X-Attachment-Id\",\"value\":\"att-001\"}],"
                + "\"body\":{\"data\":\"" + imgData + "\"},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).containsKey("att-001");
    }

    @Test
    void collectInlinePart_contentLocationHeader_usedWhenNoOtherCidHeader() throws Exception {
        final String htmlData = b64("<html><body>test</body></html>");
        final String imgData = Base64.getUrlEncoder().encodeToString(new byte[]{4, 5, 6});
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/gif\","
                + "\"headers\":[{\"name\":\"Content-Location\",\"value\":\"loc-001\"}],"
                + "\"body\":{\"data\":\"" + imgData + "\"},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).containsKey("loc-001");
    }

    @Test
    void collectInlinePart_duplicateCid_secondPartSkipped() throws Exception {
        // Two parts with the same Content-ID → second returns early (cidMap.containsKey)
        final String htmlData = b64("<html><body>test</body></html>");
        final String imgData1 = Base64.getUrlEncoder().encodeToString(new byte[]{1, 2, 3});
        final String imgData2 = Base64.getUrlEncoder().encodeToString(new byte[]{4, 5, 6});
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/jpeg\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<dup>\"}],"
                + "\"body\":{\"data\":\"" + imgData1 + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/png\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<dup>\"}],"
                + "\"body\":{\"data\":\"" + imgData2 + "\"},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        // First part wins; value starts with image/jpeg (not image/png)
        assertThat(result.get().inlineCidData().get("dup")).startsWith("data:image/jpeg;base64,");
    }

    @Test
    void collectInlinePart_blankInlineDataNoAttachmentId_nothingAddedToMap() throws Exception {
        // Part has Content-ID but body has neither "data" nor "attachmentId"
        // → data == null, body.has("attachmentId") = false → nothing added
        final String htmlData = b64("<html><body>test</body></html>");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/jpeg\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<empty-cid>\"}],"
                + "\"body\":{},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).doesNotContainKey("empty-cid");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // fetchAttachment branches (exercised through collectInlinePart)
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void fetchAttachment_successWithData_cidPopulated() throws Exception {
        final String htmlData = b64("<html><body>test</body></html>");
        final byte[] raw = {10, 20, 30};
        final String attachmentBase64 = Base64.getUrlEncoder().encodeToString(raw);
        // Part has Content-ID, no inline data, but an attachmentId
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/jpeg\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<att-img>\"}],"
                + "\"body\":{\"attachmentId\":\"ATT001\"},\"parts\":[]}"
                + "]}}");
        final JsonNode attachmentResp = json("{\"data\":\"" + attachmentBase64 + "\"}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message))
                .thenReturn(ResponseEntity.ok(attachmentResp));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).containsKey("att-img");
    }

    @Test
    void fetchAttachment_responseBodyNull_nothingAddedToMap() throws Exception {
        final String htmlData = b64("<html><body>test</body></html>");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/jpeg\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<att-null>\"}],"
                + "\"body\":{\"attachmentId\":\"ATT002\"},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message))
                .thenReturn(ResponseEntity.ok((JsonNode) null)); // attachment fetch returns null body

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).doesNotContainKey("att-null");
    }

    @Test
    void fetchAttachment_responseHasNoDataField_nothingAddedToMap() throws Exception {
        final String htmlData = b64("<html><body>test</body></html>");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/jpeg\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<att-nodata>\"}],"
                + "\"body\":{\"attachmentId\":\"ATT003\"},\"parts\":[]}"
                + "]}}");
        // Attachment response exists but has no "data" field
        final JsonNode attachmentResp = json("{\"size\":100}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message))
                .thenReturn(ResponseEntity.ok(attachmentResp));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).doesNotContainKey("att-nodata");
    }

    @Test
    void fetchAttachment_exchangeThrows_nothingAddedToMap() throws Exception {
        // fetchAttachment catches its own exception → data stays null → nothing added to cidMap
        final String htmlData = b64("<html><body>test</body></html>");
        final JsonNode message = json("{\"internalDate\":" + RECENT_DATE_MS + ","
                + "\"payload\":{\"mimeType\":\"multipart/related\",\"headers\":[],\"body\":{},"
                + "\"parts\":["
                + "{\"mimeType\":\"text/html\",\"headers\":[],"
                + "\"body\":{\"data\":\"" + htmlData + "\"},\"parts\":[]},"
                + "{\"mimeType\":\"image/jpeg\","
                + "\"headers\":[{\"name\":\"Content-ID\",\"value\":\"<att-throws>\"}],"
                + "\"body\":{\"attachmentId\":\"ATT004\"},\"parts\":[]}"
                + "]}}");
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(searchResult("msg1")))
                .thenReturn(ResponseEntity.ok(message))
                .thenThrow(new RuntimeException("attachment fetch failed"));

        final Optional<GmailDigestPayload> result = client.fetchLatestDigest(TOKEN);
        assertThat(result).isPresent();
        assertThat(result.get().inlineCidData()).doesNotContainKey("att-throws");
    }
}
