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
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.Block;
import software.amazon.awssdk.services.textract.model.BlockType;
import software.amazon.awssdk.services.textract.model.BoundingBox;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextRequest;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextResponse;
import software.amazon.awssdk.services.textract.model.Geometry;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;

/**
 * End-to-end coverage for Task 3.14.4: a full USPS Informed Delivery digest HTML is parsed
 * through the real {@link GmailParser} and real {@link MailpieceOcrService}, with only the AWS
 * {@link TextractClient} boundary mocked. This exercises the entire chain:
 * HTML -> GmailParser -> "metadata insufficient" decision -> MailpieceOcrService -> Textract.
 */
@ExtendWith(MockitoExtension.class)
class GmailParserOcrFallbackE2ETest {

    private static final OffsetDateTime RECEIVED_AT =
            OffsetDateTime.of(2025, 3, 3, 8, 30, 0, 0, ZoneOffset.ofHours(-5));

    @Mock
    private TextractClient textractClient;

    private GmailParser parser;

    @BeforeEach
    void setUp() {
        MailpieceOcrService ocrService = new MailpieceOcrService(textractClient);
        parser = new GmailParser();
        parser.setMailpieceOcrService(ocrService);
    }

    private Block line(String text, double top, double left) {
        return Block.builder()
                .blockType(BlockType.LINE)
                .text(text)
                .geometry(Geometry.builder()
                        .boundingBox(BoundingBox.builder()
                                .top((float) top)
                                .left((float) left)
                                .build())
                        .build())
                .build();
    }

    private DetectDocumentTextResponse response(Block... blocks) {
        return DetectDocumentTextResponse.builder().blocks(java.util.Arrays.asList(blocks)).build();
    }

    private String loadDigestHtml() throws IOException {
        return Files.readString(Path.of("src/test/resources/usps/gmail-digest-ocr-fallback.html"));
    }

    @Test
    @DisplayName("E2E: full digest parse triggers Textract OCR only for mailpieces with insufficient metadata")
    void fullDigest_ocrFallbackAppliedWhereMetadataInsufficient() throws Exception {
        lenient().when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(response(
                        line("Regional Medical Center", 0.03, 0.04),
                        line("Lab results available", 0.09, 0.04),
                        line("1234 Health Pkwy", 0.14, 0.04)));

        final GmailDigestPayload payload = new GmailDigestPayload(loadDigestHtml(), Map.of(), RECEIVED_AT);
        final USPSDigest digest = parser.toDomain(payload);

        assertThat(digest).isNotNull();
        assertThat(digest.mailpieces()).hasSize(3);

        // Mailpiece 1: no metadata -> OCR supplies sender, and summary falls back to OCR summary line.
        final MailPiece m1 = digest.mailpieces().get(0);
        assertThat(m1.getSender()).isEqualTo("Regional Medical Center");
        assertThat(m1.getSubject()).isEqualTo("Lab results available");

        // Mailpiece 2: generic "image" metadata -> OCR supplies both sender and summary.
        final MailPiece m2 = digest.mailpieces().get(1);
        assertThat(m2.getSender()).isEqualTo("Regional Medical Center");
        assertThat(m2.getSubject()).isEqualTo("Lab results available");

        // Mailpiece 3: complete HTML metadata -> OCR values must NOT override it.
        final MailPiece m3 = digest.mailpieces().get(2);
        assertThat(m3.getSender()).isEqualTo("Trusted Insurance Co");
        assertThat(m3.getSubject()).isEqualTo("Your policy documents are enclosed.");
    }

    @Test
    @DisplayName("E2E: when Textract yields no usable sender, insufficient-metadata mailpieces keep null sender")
    void fullDigest_ocrReturnsNothing_leavesMetadataUntouched() throws Exception {
        lenient().when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(response(line("99", 0.02, 0.02))); // no letters -> not a sender

        final GmailDigestPayload payload = new GmailDigestPayload(loadDigestHtml(), Map.of(), RECEIVED_AT);
        final USPSDigest digest = parser.toDomain(payload);

        assertThat(digest.mailpieces()).hasSize(3);
        assertThat(digest.mailpieces().get(0).getSender()).isNull();

        // The mailpiece with full metadata is still intact regardless of OCR outcome.
        final MailPiece m3 = digest.mailpieces().get(2);
        assertThat(m3.getSender()).isEqualTo("Trusted Insurance Co");
        assertThat(m3.getSubject()).isEqualTo("Your policy documents are enclosed.");
    }
}
