package com.careconnect.service;

import com.careconnect.dto.UploadedFileDTO;
import lombok.extern.slf4j.Slf4j;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.pdfbox.Loader;
import org.apache.poi.hwpf.HWPFDocument;
import org.apache.poi.hwpf.extractor.WordExtractor;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xwpf.usermodel.XWPFParagraph;
import org.apache.tika.Tika;
import org.apache.tika.exception.TikaException;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Base64;

/**
 * Service for processing various document formats and extracting text content
 */
@Slf4j
@Service
public class DocumentProcessingService {

    private static final int MAX_DOCUMENT_CONTENT_LENGTH = 15000;
    private static final int MAX_TEXT_CONTENT_LENGTH = 10000;

    private final Tika tika = new Tika();

    /**
     * Extract text content from uploaded file based on its type
     */
    public String extractTextContent(UploadedFileDTO file) {
        try {
            String filename = file.getFilename();
            String contentType = file.getContentType();
            String content = file.getContent();

            // Determine file type
            String fileType = getFileType(filename, contentType);


            switch (fileType.toLowerCase()) {
                case "pdf":
                    return extractPdfContent(content, filename);

                case "doc":
                    return extractDocContent(content, filename);

                case "docx":
                    return extractDocxContent(content, filename);

                case "text":
                case "txt":
                case "md":
                    return extractTextFileContent(content);

                case "json":
                    return extractJsonContent(content);

                case "csv":
                    return extractCsvContent(content);

                default:
                    return extractGenericContent(content, filename);
            }
        } catch (Exception e) {
            log.error("Error extracting content from file {}: {}", file.getFilename(), e.getMessage());
            return "[Error processing file: " + e.getMessage() + "]";
        }
    }

    /**
     * Extract text from PDF files using Apache PDFBox
     */
    private String extractPdfContent(String base64Content, String filename) {
        try {
            if (base64Content == null || base64Content.trim().isEmpty()) {
                return "[Empty PDF file: " + filename + "]";
            }

            // Decode base64 content
            byte[] pdfBytes = Base64.getDecoder().decode(base64Content);

            try (PDDocument document = Loader.loadPDF(pdfBytes)) {

                PDFTextStripper stripper = new PDFTextStripper();
                String text = stripper.getText(document);

                if (text == null || text.trim().isEmpty()) {
                    return "[PDF file contains no extractable text: " + filename + "]";
                }

                // Clean up the text
                text = cleanExtractedText(text);

                // Limit content length for AI processing
                if (text.length() > MAX_DOCUMENT_CONTENT_LENGTH) {
                    text = text.substring(0, MAX_DOCUMENT_CONTENT_LENGTH) + "\n... [PDF content truncated for processing]";
                }

                return text;
            }
        } catch (Exception e) {
            log.error("Error extracting PDF content from {}: {}", filename, e.getMessage());
            return "[Error extracting PDF content: " + e.getMessage() + "]";
        }
    }

    /**
     * Extract text from .doc files using Apache POI
     */
    private String extractDocContent(String base64Content, String filename) {
        try {
            if (base64Content == null || base64Content.trim().isEmpty()) {
                return "[Empty DOC file: " + filename + "]";
            }

            // Decode base64 content
            byte[] docBytes = Base64.getDecoder().decode(base64Content);

            try (InputStream inputStream = new ByteArrayInputStream(docBytes);
                 HWPFDocument document = new HWPFDocument(inputStream)) {

                WordExtractor extractor = new WordExtractor(document);
                String text = extractor.getText();

                if (text == null || text.trim().isEmpty()) {
                    return "[DOC file contains no extractable text: " + filename + "]";
                }

                // Clean up the text
                text = cleanExtractedText(text);

                // Limit content length for AI processing
                if (text.length() > MAX_DOCUMENT_CONTENT_LENGTH) {
                    text = text.substring(0, MAX_DOCUMENT_CONTENT_LENGTH) + "\n... [DOC content truncated for processing]";
                }

                return text;
            }
        } catch (Exception e) {
            log.error("Error extracting DOC content from {}: {}", filename, e.getMessage());
            return "[Error extracting DOC content: " + e.getMessage() + "]";
        }
    }

    /**
     * Extract text from .docx files using Apache POI
     */
    private String extractDocxContent(String base64Content, String filename) {
        try {
            if (base64Content == null || base64Content.trim().isEmpty()) {
                return "[Empty DOCX file: " + filename + "]";
            }

            // Decode base64 content
            byte[] docxBytes = Base64.getDecoder().decode(base64Content);

            try (InputStream inputStream = new ByteArrayInputStream(docxBytes);
                 XWPFDocument document = new XWPFDocument(inputStream)) {

                StringBuilder text = new StringBuilder();

                // Extract text from paragraphs
                for (XWPFParagraph paragraph : document.getParagraphs()) {
                    String paragraphText = paragraph.getText();
                    if (paragraphText != null && !paragraphText.trim().isEmpty()) {
                        text.append(paragraphText).append("\n");
                    }
                }

                String extractedText = text.toString();

                if (extractedText.trim().isEmpty()) {
                    return "[DOCX file contains no extractable text: " + filename + "]";
                }

                // Clean up the text
                extractedText = cleanExtractedText(extractedText);

                // Limit content length for AI processing
                if (extractedText.length() > MAX_DOCUMENT_CONTENT_LENGTH) {
                    extractedText = extractedText.substring(0, MAX_DOCUMENT_CONTENT_LENGTH) + "\n... [DOCX content truncated for processing]";
                }

                return extractedText;
            }
        } catch (Exception e) {
            log.error("Error extracting DOCX content from {}: {}", filename, e.getMessage());
            return "[Error extracting DOCX content: " + e.getMessage() + "]";
        }
    }

    /**
     * Extract text from plain text files
     */
    private String extractTextFileContent(String content) {
        if (content == null || content.trim().isEmpty()) {
            return "[Empty text file]";
        }

        // If content is base64 encoded, decode it
        if (isBase64Encoded(content)) {
            try {
                byte[] decoded = Base64.getDecoder().decode(content);
                content = new String(decoded);
            } catch (Exception e) {
                log.warn("Failed to decode base64 text content: {}", e.getMessage());
            }
        }

        // Limit content length for AI processing
        if (content.length() > MAX_TEXT_CONTENT_LENGTH) {
            content = content.substring(0, MAX_TEXT_CONTENT_LENGTH) + "\n... [Text content truncated for processing]";
        }

        return content;
    }

    /**
     * Extract and format JSON content
     */
    private String extractJsonContent(String content) {
        if (content == null || content.trim().isEmpty()) {
            return "[Empty JSON file]";
        }

        // If content is base64 encoded, decode it
        if (isBase64Encoded(content)) {
            try {
                byte[] decoded = Base64.getDecoder().decode(content);
                content = new String(decoded);
            } catch (Exception e) {
                log.warn("Failed to decode base64 JSON content: {}", e.getMessage());
            }
        }

        // Try to format JSON for better readability
        try {
            // Simple JSON formatting - in a real implementation, you'd use a proper JSON library
            content = content.replaceAll("\\{", "{\n  ")
                    .replaceAll("\\}", "\n}")
                    .replaceAll(",", ",\n  ");
        } catch (Exception e) {
            // If formatting fails, use original content
        }

        // Limit content length
        if (content.length() > MAX_TEXT_CONTENT_LENGTH) {
            content = content.substring(0, MAX_TEXT_CONTENT_LENGTH) + "\n... [JSON content truncated for processing]";
        }

        return content;
    }

    /**
     * Extract CSV content
     */
    private String extractCsvContent(String content) {
        if (content == null || content.trim().isEmpty()) {
            return "[Empty CSV file]";
        }

        // If content is base64 encoded, decode it
        if (isBase64Encoded(content)) {
            try {
                byte[] decoded = Base64.getDecoder().decode(content);
                content = new String(decoded);
            } catch (Exception e) {
                log.warn("Failed to decode base64 CSV content: {}", e.getMessage());
            }
        }

        // Limit content length
        if (content.length() > MAX_TEXT_CONTENT_LENGTH) {
            content = content.substring(0, MAX_TEXT_CONTENT_LENGTH) + "\n... [CSV content truncated for processing]";
        }

        return content;
    }

    /**
     * Extract content using Apache Tika for generic file types
     */
    private String extractGenericContent(String content, String filename) {
        try {
            if (content == null || content.trim().isEmpty()) {
                return "[Empty file: " + filename + "]";
            }

            // If content is base64 encoded, decode it
            if (isBase64Encoded(content)) {
                try {
                    byte[] decoded = Base64.getDecoder().decode(content);
                    content = new String(decoded);
                } catch (Exception e) {
                    log.warn("Failed to decode base64 content for {}: {}", filename, e.getMessage());
                    return "[Binary file: " + filename + " - Content not readable as text]";
                }
            }

            // Try to extract text using Tika
            try (InputStream inputStream = new ByteArrayInputStream(content.getBytes())) {
                String extractedText = tika.parseToString(inputStream);

                if (extractedText == null || extractedText.trim().isEmpty()) {
                    return "[File contains no extractable text: " + filename + "]";
                }

                // Clean up the text
                extractedText = cleanExtractedText(extractedText);

                // Limit content length
                if (extractedText.length() > MAX_TEXT_CONTENT_LENGTH) {
                    extractedText = extractedText.substring(0, MAX_TEXT_CONTENT_LENGTH) + "\n... [Content truncated for processing]";
                }

                return extractedText;
            }
        } catch (TikaException | IOException e) {
            log.warn("Tika extraction failed for {}: {}", filename, e.getMessage());
            return "[Unable to extract text from: " + filename + "]";
        }
    }

    /**
     * Determine file type from filename and content type
     */
    private String getFileType(String filename, String contentType) {
        if (filename != null) {
            String extension = filename.substring(filename.lastIndexOf('.') + 1).toLowerCase();
            return extension;
        }

        if (contentType != null) {
            if (contentType.startsWith("text/")) return "text";
            if (contentType.startsWith("image/")) return "image";
            if (contentType.startsWith("application/pdf")) return "pdf";
            if (contentType.startsWith("application/json")) return "json";
            if (contentType.startsWith("text/csv")) return "csv";
            if (contentType.contains("wordprocessingml")) return "docx";
            if (contentType.contains("msword")) return "doc";
        }

        return "unknown";
    }

    /**
     * Check if content is base64 encoded
     */
    private boolean isBase64Encoded(String content) {
        if (content == null || content.trim().isEmpty()) {
            return false;
        }

        // Simple check - base64 strings are typically longer and contain only base64 characters
        if (content.length() < 100) {
            return false;
        }

        // Performance optimization: check only the first 1000 characters for base64 pattern
        String sample = content.length() > 1000 ? content.substring(0, 1000) : content;

        // Base64 characters: A-Z, a-z, 0-9, +, /, = (for padding)
        // Also check for typical base64 characteristics
        if (!sample.matches("^[A-Za-z0-9+/]*={0,2}$")) {
            return false;
        }

        // Verify with actual decoding on small sample to be sure
        try {
            Base64.getDecoder().decode(sample.replaceAll("=+$", "")); // Remove padding for test
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Clean up extracted text by removing excessive whitespace and formatting
     */
    private String cleanExtractedText(String text) {
        if (text == null) {
            return "";
        }

        // Remove excessive whitespace
        text = text.replaceAll("\\s+", " ");

        // Remove excessive line breaks
        text = text.replaceAll("\n\\s*\n\\s*\n+", "\n\n");

        // Trim whitespace
        text = text.trim();

        return text;
    }
}
