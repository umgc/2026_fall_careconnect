package com.careconnect.service;

import com.careconnect.dto.GmailDigestPayload;
import com.careconnect.model.MailPiece;
import com.careconnect.model.USPSDigest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class GmailParserOcrFallbackTest {

    private static final OffsetDateTime NOW = OffsetDateTime.now(ZoneOffset.UTC);
    private static final String DATA_URL = "data:image/jpeg;base64,QUJD"; // "ABC"

    @Mock
    private MailpieceOcrService mailpieceOcrService;

    private GmailParser parser;

    @BeforeEach
    void setUp() {
        parser = new GmailParser();
        parser.setMailpieceOcrService(mailpieceOcrService);
    }

    @Test
    @DisplayName("OCR fallback fills sender when HTML metadata is insufficient")
    void toDomain_ocrFallback_fillsSenderWhenMetadataInsufficient() throws Exception {
        when(mailpieceOcrService.extractMailpieceMetadata(any(byte[].class), eq("image/jpeg;base64")))
                .thenReturn(Optional.of(new MailpieceOcrResult("Acme Medical Billing", null)));

        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='" + DATA_URL + "' alt='just a letter'>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(new GmailDigestPayload(html, Map.of(), NOW));

        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSender()).isEqualTo("Acme Medical Billing");
        verify(mailpieceOcrService).extractMailpieceMetadata(any(byte[].class), eq("image/jpeg;base64"));
    }

    @Test
    @DisplayName("OCR is skipped when sender metadata is already present")
    void toDomain_ocrSkipped_whenSenderMetadataPresent() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='" + DATA_URL + "' alt='just a letter'>"
                + "<span class='sender'>Known Sender</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(new GmailDigestPayload(html, Map.of(), NOW));

        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSender()).isEqualTo("Known Sender");
        verify(mailpieceOcrService, never()).extractMailpieceMetadata(any(), any());
    }

    @Test
    @DisplayName("OCR fallback enriches generic summary from second OCR line")
    void toDomain_ocrFallback_enrichesGenericSummary() throws Exception {
        when(mailpieceOcrService.extractMailpieceMetadata(any(byte[].class), eq("image/jpeg;base64")))
                .thenReturn(Optional.of(new MailpieceOcrResult("State Farm", "Policy renewal notice")));

        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='" + DATA_URL + "' alt='mail'>"
                + "<span class='sender'>State Farm</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(new GmailDigestPayload(html, Map.of(), NOW));

        final MailPiece mailpiece = digest.mailpieces().get(0);
        assertThat(mailpiece.getSender()).isEqualTo("State Farm");
        assertThat(mailpiece.getSubject()).isEqualTo("Policy renewal notice");
    }

    @Test
    @DisplayName("Campaign mailpiece uses OCR when campaign metadata is missing")
    void toDomain_campaignMailPieces_ocrFallbackWhenMetadataInsufficient() throws Exception {
        final Map<String, String> cids = Map.of("mailpiece-abc", DATA_URL);
        when(mailpieceOcrService.extractMailpieceMetadata(any(byte[].class), eq("image/jpeg;base64")))
                .thenReturn(Optional.of(new MailpieceOcrResult("County Health Dept", "Appointment reminder")));

        final String html = "<html><body><div id='mail-section'><table class='mail'>"
                + "<tr><td><img data-inline-cid='mailpiece-abc' src='cid:mailpiece-abc' alt='image'></td></tr>"
                + "</table></div></body></html>";
        final USPSDigest digest = parser.toDomain(new GmailDigestPayload(html, cids, NOW));

        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSender()).isEqualTo("County Health Dept");
        assertThat(digest.mailpieces().get(0).getSubject()).isEqualTo("Appointment reminder");
    }

    @Test
    @DisplayName("OCR is not invoked for non-data image URLs")
    void toDomain_ocrSkipped_forNonDataImageUrls() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='https://example.com/mailpiece.jpg' alt='just a letter'>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(new GmailDigestPayload(html, Map.of(), NOW));

        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSender()).isNull();
        verify(mailpieceOcrService, never()).extractMailpieceMetadata(any(), any());
    }
}
