package com.careconnect.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.Block;
import software.amazon.awssdk.services.textract.model.BlockType;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextRequest;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextResponse;
import software.amazon.awssdk.services.textract.model.Document;

import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true")
public class MailpieceOcrService {

    private final TextractClient textractClient;

    /**
     * Runs AWS Textract over the given mailpiece image bytes and attempts to extract the
     * top-left text line, which generally contains the sender name.
     *
     * @param imageBytes the image contents (PNG/JPEG, etc.)
     * @param metadata   optional data URL metadata (e.g., "image/jpeg;base64") for logging
     * @return optional sender name candidate
     */
    public Optional<String> extractTopLeftLabel(byte[] imageBytes, String metadata) {
        return extractMailpieceMetadata(imageBytes, metadata).map(MailpieceOcrResult::sender);
    }

    /**
     * Runs AWS Textract and returns sender plus an optional second top-region line for summary
     * enrichment when HTML metadata is insufficient.
     */
    public Optional<MailpieceOcrResult> extractMailpieceMetadata(byte[] imageBytes, String metadata) {
        if (imageBytes == null || imageBytes.length == 0) {
            return Optional.empty();
        }
        try {
            DetectDocumentTextResponse response = textractClient.detectDocumentText(
                    DetectDocumentTextRequest.builder()
                            .document(Document.builder()
                                    .bytes(SdkBytes.fromByteArray(imageBytes))
                                    .build())
                            .build()
            );

            List<String> topRegionLines = collectTopRegionLines(response);
            if (topRegionLines.isEmpty()) {
                return Optional.empty();
            }

            String sender = topRegionLines.stream()
                    .filter(this::looksLikeSender)
                    .findFirst()
                    .orElse(null);
            if (sender == null) {
                return Optional.empty();
            }

            String summaryLine = topRegionLines.stream()
                    .filter(this::looksLikeSummary)
                    .filter(line -> !line.equalsIgnoreCase(sender))
                    .findFirst()
                    .orElse(null);

            log.info("Mailpiece OCR detected sender '{}'{}", sender,
                    summaryLine != null ? " with summary hint '" + summaryLine + "'" : "");
            return Optional.of(new MailpieceOcrResult(sender, summaryLine));

        } catch (Exception ex) {
            log.warn("Textract mailpiece OCR failed ({}): {}", metadata, ex.getMessage());
            return Optional.empty();
        }
    }

    private List<String> collectTopRegionLines(DetectDocumentTextResponse response) {
        List<Block> lines = response.blocks().stream()
                .filter(b -> b.blockType() == BlockType.LINE)
                .filter(b -> b.geometry() != null && b.geometry().boundingBox() != null)
                .collect(Collectors.toList());

        if (lines.isEmpty()) {
            return List.of();
        }

        lines.sort(Comparator
                .comparingDouble((Block b) -> b.geometry().boundingBox().top())
                .thenComparingDouble(b -> b.geometry().boundingBox().left()));

        double minTop = lines.get(0).geometry().boundingBox().top();
        double threshold = minTop + 0.15;

        return lines.stream()
                .filter(b -> b.geometry().boundingBox().top() <= threshold)
                .sorted(Comparator
                        .comparingDouble((Block b) -> b.geometry().boundingBox().top())
                        .thenComparingDouble(b -> b.geometry().boundingBox().left()))
                .map(block -> {
                    String text = block.text();
                    log.debug("Mailpiece OCR candidate: '{}' (top={}, left={})",
                            text,
                            block.geometry().boundingBox().top(),
                            block.geometry().boundingBox().left());
                    return text;
                })
                .map(String::trim)
                .filter(text -> !text.isBlank())
                .collect(Collectors.toList());
    }

    private boolean looksLikeSender(String text) {
        if (text == null || text.isBlank()) {
            return false;
        }
        String cleaned = text.strip();
        if (cleaned.length() < 3) {
            return false;
        }
        String lower = cleaned.toLowerCase(Locale.ROOT);
        if (lower.startsWith("learn more")) {
            return false;
        }
        if (lower.contains("click") || lower.contains("visit")) {
            return false;
        }
        if (lower.contains("ridealong") || lower.contains("ride along")) {
            return false;
        }
        if (lower.equals("campaign") || lower.equals("mail") || lower.equals("image")) {
            return false;
        }
        // Require at least one letter to avoid purely numeric tracking numbers.
        return cleaned.matches(".*[A-Za-z].*");
    }

    private boolean looksLikeSummary(String text) {
        if (text == null || text.isBlank() || text.length() < 3) {
            return false;
        }
        String lower = text.strip().toLowerCase(Locale.ROOT);
        if (lower.startsWith("learn more") || lower.contains("click") || lower.contains("visit")) {
            return false;
        }
        if (lower.contains("ridealong") || lower.contains("ride along")) {
            return false;
        }
        return lower.matches(".*[a-z].*");
    }
}
