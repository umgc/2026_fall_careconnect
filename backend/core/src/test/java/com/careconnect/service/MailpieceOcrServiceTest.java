package com.careconnect.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.Block;
import software.amazon.awssdk.services.textract.model.BlockType;
import software.amazon.awssdk.services.textract.model.BoundingBox;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextRequest;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextResponse;
import software.amazon.awssdk.services.textract.model.Geometry;

import java.util.Arrays;
import java.util.Collections;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

class MailpieceOcrServiceTest {

    @Mock
    private TextractClient textractClient;

    @InjectMocks
    private MailpieceOcrService mailpieceOcrService;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private Block lineBlock(String text, double top, double left) {
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

    private Block wordBlock(String text) {
        return Block.builder()
                .blockType(BlockType.WORD)
                .text(text)
                .build();
    }

    private Block lineBlockNoGeometry(String text) {
        return Block.builder()
                .blockType(BlockType.LINE)
                .text(text)
                .build();
    }

    private Block lineBlockNullBoundingBox(String text) {
        return Block.builder()
                .blockType(BlockType.LINE)
                .text(text)
                .geometry(Geometry.builder().build())
                .build();
    }

    private DetectDocumentTextResponse responseWithBlocks(Block... blocks) {
        return DetectDocumentTextResponse.builder()
                .blocks(Arrays.asList(blocks))
                .build();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // extractTopLeftLabel - null / empty input
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractTopLeftLabel - null imageBytes - returns empty")
    void extractTopLeftLabel_nullImageBytes_returnsEmpty() throws Exception {
        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(null, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - empty imageBytes - returns empty")
    void extractTopLeftLabel_emptyImageBytes_returnsEmpty() throws Exception {
        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(new byte[0], "meta");
        assertThat(result).isEmpty();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // extractTopLeftLabel - no LINE blocks
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractTopLeftLabel - no line blocks after filtering - returns empty")
    void extractTopLeftLabel_noLineBlocks_returnsEmpty() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(wordBlock("Some word")));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "image/png");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - line blocks with no geometry filtered out - returns empty if none remain")
    void extractTopLeftLabel_lineBlocksNoGeometry_returnsEmpty() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlockNoGeometry("No geometry"),
                        lineBlockNullBoundingBox("Null bounding box")));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "image/png");
        assertThat(result).isEmpty();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // extractTopLeftLabel - textract exception
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractTopLeftLabel - textract throws exception - returns empty")
    void extractTopLeftLabel_textractThrows_returnsEmpty() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenThrow(new RuntimeException("AWS error"));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "image/jpeg;base64");
        assertThat(result).isEmpty();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // extractTopLeftLabel - happy path with valid sender
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractTopLeftLabel - valid sender in top left - returns sender name")
    void extractTopLeftLabel_validSender_returnsSenderName() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("USPS Headquarters", 0.05, 0.05),
                        lineBlock("Some lower text", 0.80, 0.50)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "image/png");
        assertThat(result).isPresent();
        assertThat(result.get()).isEqualTo("USPS Headquarters");
    }

    @Test
    @DisplayName("extractTopLeftLabel - multiple blocks in top region - returns first valid sender")
    void extractTopLeftLabel_multipleTopBlocks_returnsFirstValidSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("ABC Corporation", 0.02, 0.10),
                        lineBlock("123 Main Street", 0.10, 0.10),
                        lineBlock("Some far away text", 0.90, 0.50)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, null);
        assertThat(result).isPresent();
        assertThat(result.get()).isEqualTo("ABC Corporation");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // extractTopLeftLabel - blocks outside threshold
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractTopLeftLabel - all valid blocks below threshold - returns empty when none pass looksLikeSender")
    void extractTopLeftLabel_allBlocksBelowThreshold_returnsEmpty() throws Exception {
        // Single block at top that does not look like a sender (too short)
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("AB", 0.05, 0.05)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // looksLikeSender - various filter cases
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractTopLeftLabel - blank text in top region - filtered by looksLikeSender")
    void extractTopLeftLabel_blankText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("   ", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text shorter than 3 chars - filtered by looksLikeSender")
    void extractTopLeftLabel_shortText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("AB", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text starts with 'learn more' - filtered by looksLikeSender")
    void extractTopLeftLabel_learnMoreText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Learn More about us", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text contains 'click' - filtered by looksLikeSender")
    void extractTopLeftLabel_clickText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Click here for details", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text contains 'visit' - filtered by looksLikeSender")
    void extractTopLeftLabel_visitText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Visit our website today", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text contains 'ridealong' - filtered by looksLikeSender")
    void extractTopLeftLabel_ridealongText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Special ridealong offer", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text contains 'ride along' - filtered by looksLikeSender")
    void extractTopLeftLabel_rideAlongText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Some ride along text here", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text equals 'campaign' - filtered by looksLikeSender")
    void extractTopLeftLabel_campaignText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("campaign", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text equals 'mail' - filtered by looksLikeSender")
    void extractTopLeftLabel_mailText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("mail", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - text equals 'image' - filtered by looksLikeSender")
    void extractTopLeftLabel_imageText_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("image", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - purely numeric text - filtered by looksLikeSender (no letters)")
    void extractTopLeftLabel_purelyNumeric_filteredByLooksLikeSender() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("123456789", 0.02, 0.02)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // extractTopLeftLabel - sorting and threshold behavior
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractTopLeftLabel - top-left sorting selects correct block - returns leftmost among topmost")
    void extractTopLeftLabel_topLeftSorting_returnsLeftmostAmongTopmost() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Right Sender", 0.02, 0.60),
                        lineBlock("Left Sender", 0.02, 0.01),
                        lineBlock("Below Threshold", 0.50, 0.01)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isPresent();
        assertThat(result.get()).isEqualTo("Left Sender");
    }

    @Test
    @DisplayName("extractTopLeftLabel - first candidate fails looksLikeSender but second passes - returns second")
    void extractTopLeftLabel_firstFailsSecondPasses_returnsSecond() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("123", 0.01, 0.01), // no letters
                        lineBlock("Valid Sender Inc", 0.05, 0.05)));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isPresent();
        assertThat(result.get()).isEqualTo("Valid Sender Inc");
    }

    @Test
    @DisplayName("extractTopLeftLabel - null metadata - still works correctly")
    void extractTopLeftLabel_nullMetadata_stillWorks() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenThrow(new RuntimeException("error"));

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, null);
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - lines list empty after geometry filter - returns empty")
    void extractTopLeftLabel_emptyLinesAfterFilter_returnsEmpty() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(DetectDocumentTextResponse.builder()
                        .blocks(Collections.emptyList())
                        .build());

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("extractTopLeftLabel - all top candidates fail looksLikeSender - returns empty")
    void extractTopLeftLabel_allTopCandidatesFail_returnsEmpty() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("AB", 0.01, 0.01), // too short
                        lineBlock("Learn More stuff", 0.02, 0.01), // starts with learn more
                        lineBlock("999888777", 0.03, 0.01))); // no letters

        final Optional<String> result = mailpieceOcrService.extractTopLeftLabel(
                new byte[] { 1, 2, 3 }, "meta");
        assertThat(result).isEmpty();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // extractMailpieceMetadata - sender + summary enrichment
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    @DisplayName("extractMailpieceMetadata - returns sender and summary line from top region")
    void extractMailpieceMetadata_returnsSenderAndSummaryLine() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Acme Corp", 0.02, 0.05),
                        lineBlock("Invoice enclosed", 0.08, 0.05),
                        lineBlock("Footer text", 0.90, 0.50)));

        final Optional<MailpieceOcrResult> result = mailpieceOcrService.extractMailpieceMetadata(
                new byte[] { 1, 2, 3 }, "image/png");
        assertThat(result).isPresent();
        assertThat(result.get().sender()).isEqualTo("Acme Corp");
        assertThat(result.get().summaryLine()).isEqualTo("Invoice enclosed");
    }

    @Test
    @DisplayName("extractMailpieceMetadata - summary line omitted when only sender is present")
    void extractMailpieceMetadata_summaryOmittedWhenOnlySenderPresent() throws Exception {
        when(textractClient.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(responseWithBlocks(
                        lineBlock("Solo Sender LLC", 0.02, 0.05)));

        final Optional<MailpieceOcrResult> result = mailpieceOcrService.extractMailpieceMetadata(
                new byte[] { 1, 2, 3 }, "image/png");
        assertThat(result).isPresent();
        assertThat(result.get().sender()).isEqualTo("Solo Sender LLC");
        assertThat(result.get().summaryLine()).isNull();
    }
}
