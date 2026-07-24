package com.careconnect.service;

import com.careconnect.model.MailPiece;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

class MailpieceNormalizerTest {

    private MailpieceNormalizer normalizer;

    @BeforeEach
    void setUp() {
        normalizer = new MailpieceNormalizer();
    }

    @Test
    @DisplayName("normalize builds stable source_key and content_hash")
    void normalize_buildsStableSourceKeyAndHash() {
        final OffsetDateTime digestDate = OffsetDateTime.of(2025, 3, 3, 12, 0, 0, 0, ZoneOffset.UTC);
        final MailPiece piece = new MailPiece(
                "m-1", "Acme Bank", "Monthly statement",
                "https://example.com/mail.png", digestDate, null);

        final MailpieceNormalizer.NormalizedMailpiece first = normalizer.normalize(piece, digestDate);
        final MailpieceNormalizer.NormalizedMailpiece second = normalizer.normalize(piece, digestDate);

        assertThat(first.sourceKey()).isEqualTo("2025-03-03|m-1");
        assertThat(first.contentHash()).isEqualTo(second.contentHash());
        assertThat(first.contentHash()).hasSize(64);
        assertThat(first.imageRef()).isEqualTo("https://example.com/mail.png");
        assertThat(first.consentScope()).isEqualTo(MailpieceNormalizer.DEFAULT_CONSENT_SCOPE);
    }

    @Test
    @DisplayName("data: URLs are not stored as image_ref but fingerprint feeds content_hash")
    void normalize_dataUrl_notStoredAsImageRef() {
        final String dataUrl = "data:image/png;base64," + Base64.getEncoder().encodeToString(new byte[]{1, 2, 3});
        final OffsetDateTime digestDate = OffsetDateTime.of(2025, 3, 3, 8, 0, 0, 0, ZoneOffset.UTC);
        final MailPiece piece = new MailPiece("m-2", "Sender", "Summary", dataUrl, digestDate, null);

        final MailpieceNormalizer.NormalizedMailpiece normalized = normalizer.normalize(piece, digestDate);

        assertThat(normalized.imageRef()).isNull();
        assertThat(normalized.imageFingerprint()).isNotBlank();
        assertThat(normalized.contentHash()).isNotBlank();
    }

    @Test
    @DisplayName("cid: image refs are preserved")
    void normalize_preservesCidImageRef() {
        final OffsetDateTime digestDate = OffsetDateTime.of(2025, 3, 3, 8, 0, 0, 0, ZoneOffset.UTC);
        final MailPiece piece = new MailPiece(
                "m-3", "Sender", "Summary", "cid:mailpiece-abc", digestDate, null);

        final MailpieceNormalizer.NormalizedMailpiece normalized = normalizer.normalize(piece, digestDate);

        assertThat(normalized.imageRef()).isEqualTo("cid:mailpiece-abc");
    }

    @Test
    @DisplayName("blank sender remains null after sanitization")
    void normalize_blankSender_remainsNull() {
        final OffsetDateTime digestDate = OffsetDateTime.of(2025, 3, 3, 8, 0, 0, 0, ZoneOffset.UTC);
        final MailPiece piece = new MailPiece("m-4", "   ", "  Hello  ", null, digestDate, null);

        final MailpieceNormalizer.NormalizedMailpiece normalized = normalizer.normalize(piece, digestDate);

        assertThat(normalized.sender()).isNull();
        assertThat(normalized.summary()).isEqualTo("Hello");
    }
}
