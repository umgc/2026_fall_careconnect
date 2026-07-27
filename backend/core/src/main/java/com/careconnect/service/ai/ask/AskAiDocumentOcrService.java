package com.careconnect.service.ai.ask;

import com.careconnect.config.AskAiAsyncConfig;
import com.careconnect.indexing.DocumentIndexedPayload;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.UserFile;
import com.careconnect.model.ai.ask.AskAiOcrOutbox;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.ai.ask.AskAiOcrOutboxRepository;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.S3StorageService;
import com.careconnect.service.invoice.TextractService;
import com.careconnect.util.ContentHashUtil;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Async;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

/**
 * Runs Ask AI document OCR off the upload request thread.
 *
 * <p>{@link TextractService#analyzeAndGetResult} can poll AWS for minutes; calling it
 * synchronously from {@code uploadFile} would block Tomcat workers and time out clients.
 * Upload persists metadata immediately; OCR is scheduled {@code afterCommit} and reloads
 * bytes from storage by file id (no large byte[] held on the async queue).
 *
 * <p>Every enqueue also upserts {@link AskAiOcrOutbox} so queue-full rejects remain durable
 * and are retried by {@link #sweepPendingOcrJobs()}.
 */
@Service
public class AskAiDocumentOcrService {

    private static final Logger log = LoggerFactory.getLogger(AskAiDocumentOcrService.class);
    private static final String ASK_AI_OCR_S3_PREFIX = "ask-ai-docs/";
    private static final int MAX_OCR_TEXT_CHARS = 50_000;
    private static final String DEFAULT_CONSENT_SCOPE = "on_consent";
    private static final int MAX_OCR_ATTEMPTS = 5;
    private static final int SWEEP_BATCH = 20;
    private static final long STALE_SECONDS = 30L;

    private final UserFileRepository userFileRepository;
    private final AskAiOcrOutboxRepository ocrOutboxRepository;
    private final IndexingEventEmitter indexingEventEmitter;
    private final TextractService textractService;
    private final S3StorageService s3StorageService;
    private final AskAiDocumentOcrService self;

    @Autowired
    public AskAiDocumentOcrService(
            final UserFileRepository userFileRepository,
            final AskAiOcrOutboxRepository ocrOutboxRepository,
            final IndexingEventEmitter indexingEventEmitter,
            @Autowired(required = false) final TextractService textractService,
            @Autowired(required = false) final S3StorageService s3StorageService,
            @Lazy final AskAiDocumentOcrService self) {
        this.userFileRepository = userFileRepository;
        this.ocrOutboxRepository = ocrOutboxRepository;
        this.indexingEventEmitter = indexingEventEmitter;
        this.textractService = textractService;
        this.s3StorageService = s3StorageService;
        this.self = self != null ? self : this;
    }

    /**
     * Schedules OCR after the surrounding transaction commits when local extract failed
     * and the file looks like a PDF/image. No-op when AWS Textract is disabled.
     */
    public void enqueueAfterFailedExtract(final UserFile userFile) {
        if (textractService == null || userFile == null || userFile.getId() == null) {
            return;
        }
        if (!isOcrCandidate(userFile.getContentType(), userFile.getOriginalFilename())) {
            return;
        }
        final Long fileId = userFile.getId();
        self.upsertPendingOutbox(fileId);
        final Runnable schedule = () -> self.processUploadedDocumentAsync(fileId);
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    schedule.run();
                }
            });
        } else {
            schedule.run();
        }
    }

    @Transactional
    public void upsertPendingOutbox(final Long fileId) {
        final AskAiOcrOutbox row = ocrOutboxRepository.findByFileId(fileId).orElseGet(() ->
                AskAiOcrOutbox.builder()
                        .fileId(fileId)
                        .status(AskAiOcrOutbox.STATUS_PENDING)
                        .attempts(0)
                        .build());
        if (AskAiOcrOutbox.STATUS_COMPLETED.equals(row.getStatus())) {
            // Re-enqueue after a later extract failure — allow another OCR pass.
            row.setStatus(AskAiOcrOutbox.STATUS_PENDING);
            row.setAttempts(0);
            row.setLastError(null);
        } else if (AskAiOcrOutbox.STATUS_FAILED.equals(row.getStatus())) {
            row.setStatus(AskAiOcrOutbox.STATUS_PENDING);
        }
        ocrOutboxRepository.save(row);
    }

    @Async(AskAiAsyncConfig.ASK_AI_OCR_EXECUTOR)
    public void processUploadedDocumentAsync(final Long fileId) {
        try {
            self.processUploadedDocument(fileId);
        } catch (Exception e) {
            log.warn("Ask AI document OCR async job failed for fileId {}: {}", fileId, e.getMessage());
            self.markOutboxFailed(fileId, e.getMessage());
        }
    }

    /**
     * Retries durable OCR work that was dropped when the executor queue was full, or that
     * failed transiently.
     */
    @Scheduled(fixedDelayString = "${careconnect.ai.ask.ocr.sweep-interval-ms:30000}")
    public void sweepPendingOcrJobs() {
        if (textractService == null) {
            return;
        }
        final Instant staleBefore = Instant.now().minus(STALE_SECONDS, ChronoUnit.SECONDS);
        final List<AskAiOcrOutbox> batch = ocrOutboxRepository.findRetryable(
                MAX_OCR_ATTEMPTS, staleBefore, PageRequest.of(0, SWEEP_BATCH));
        for (final AskAiOcrOutbox row : batch) {
            self.processUploadedDocumentAsync(row.getFileId());
        }
    }

    @Transactional
    public void processUploadedDocument(final Long fileId) {
        if (textractService == null || fileId == null) {
            return;
        }
        final AskAiOcrOutbox outbox = ocrOutboxRepository.findByFileId(fileId).orElse(null);
        if (outbox != null) {
            outbox.setAttempts(outbox.getAttempts() + 1);
            ocrOutboxRepository.save(outbox);
        }

        final UserFile userFile = userFileRepository.findById(fileId).orElse(null);
        if (userFile == null || !isOcrCandidate(userFile.getContentType(), userFile.getOriginalFilename())) {
            markOutboxCompleted(fileId);
            return;
        }
        final byte[] bytes = loadFileBytes(userFile);
        if (bytes == null || bytes.length == 0) {
            log.warn("Ask AI document OCR skipped for fileId {}: no stored bytes", fileId);
            markOutboxFailed(fileId, "no stored bytes");
            return;
        }
        try {
            final String filename = userFile.getOriginalFilename() == null
                    ? "document.bin"
                    : userFile.getOriginalFilename();
            final String contentType = userFile.getContentType() == null
                    ? "application/octet-stream"
                    : userFile.getContentType();
            final MultipartFile ocrFile = new InMemoryMultipartFile("file", filename, contentType, bytes);
            final var result = textractService.analyzeAndGetResult(List.of(ocrFile), ASK_AI_OCR_S3_PREFIX);
            String rawText = result == null ? null : result.rawText;
            if (rawText == null || rawText.isBlank()) {
                markOutboxCompleted(fileId);
                return;
            }
            rawText = rawText.trim();
            if (rawText.length() > MAX_OCR_TEXT_CHARS) {
                rawText = rawText.substring(0, MAX_OCR_TEXT_CHARS) + "\n... [OCR text truncated]";
            }
            userFile.setExtractedText(rawText);
            final UserFile saved = userFileRepository.save(userFile);
            emitDocumentIndexed(saved);
            markOutboxCompleted(fileId);
            log.info(
                    "Ask AI document OCR extracted text for fileId={} chars={}",
                    saved.getId(),
                    rawText.length());
        } catch (Exception e) {
            log.warn("Ask AI document OCR failed for fileId {}: {}", fileId, e.getMessage());
            markOutboxFailed(fileId, e.getMessage());
        }
    }

    @Transactional
    public void markOutboxCompleted(final Long fileId) {
        ocrOutboxRepository.findByFileId(fileId).ifPresent(row -> {
            row.setStatus(AskAiOcrOutbox.STATUS_COMPLETED);
            row.setLastError(null);
            ocrOutboxRepository.save(row);
        });
    }

    @Transactional
    public void markOutboxFailed(final Long fileId, final String error) {
        ocrOutboxRepository.findByFileId(fileId).ifPresent(row -> {
            row.setStatus(AskAiOcrOutbox.STATUS_FAILED);
            row.setLastError(error == null ? null : error.substring(0, Math.min(error.length(), 1000)));
            ocrOutboxRepository.save(row);
        });
    }

    private byte[] loadFileBytes(final UserFile userFile) {
        if (userFile.getStorageType() == UserFile.StorageType.DATABASE) {
            final byte[] data = userFile.getFileData();
            if (data != null && data.length > 0) {
                return data;
            }
        }
        if (userFile.getS3Path() != null && !userFile.getS3Path().isBlank() && s3StorageService != null) {
            try {
                return s3StorageService.download(userFile.getS3Path());
            } catch (Exception e) {
                log.warn("Ask AI OCR S3 download failed for fileId {}: {}", userFile.getId(), e.getMessage());
            }
        }
        return null;
    }

    static boolean isOcrCandidate(final String contentType, final String filename) {
        final String type = contentType == null ? "" : contentType.toLowerCase();
        if (type.startsWith("image/") || type.contains("pdf")) {
            return true;
        }
        if (filename == null || filename.isBlank()) {
            return false;
        }
        final String lower = filename.toLowerCase();
        return lower.endsWith(".pdf")
                || lower.endsWith(".png")
                || lower.endsWith(".jpg")
                || lower.endsWith(".jpeg")
                || lower.endsWith(".tif")
                || lower.endsWith(".tiff")
                || lower.endsWith(".webp");
    }

    private void emitDocumentIndexed(final UserFile file) {
        if (file == null || file.getId() == null || file.getPatientId() == null) {
            return;
        }
        final String excerpt = FileManagementService.indexableDocumentText(file);
        if (excerpt == null || excerpt.isBlank()) {
            return;
        }
        try {
            final String category = file.getFileCategory() == null
                    ? null
                    : file.getFileCategory().name();
            indexingEventEmitter.emitDocumentIndexed(new DocumentIndexedPayload(
                    file.getId(),
                    file.getPatientId(),
                    ContentHashUtil.sha256(excerpt),
                    category,
                    excerpt,
                    DEFAULT_CONSENT_SCOPE));
        } catch (Exception e) {
            log.warn("Failed to emit DOCUMENT_INDEXED after OCR for fileId {}: {}",
                    file.getId(), e.getMessage());
        }
    }

    /** Minimal {@link MultipartFile} for Textract without pulling spring-test into production. */
    static final class InMemoryMultipartFile implements MultipartFile {
        private final String name;
        private final String originalFilename;
        private final String contentType;
        private final byte[] content;

        InMemoryMultipartFile(
                final String name,
                final String originalFilename,
                final String contentType,
                final byte[] content) {
            this.name = name;
            this.originalFilename = originalFilename;
            this.contentType = contentType;
            this.content = content == null ? new byte[0] : content;
        }

        @Override
        public String getName() {
            return name;
        }

        @Override
        public String getOriginalFilename() {
            return originalFilename;
        }

        @Override
        public String getContentType() {
            return contentType;
        }

        @Override
        public boolean isEmpty() {
            return content.length == 0;
        }

        @Override
        public long getSize() {
            return content.length;
        }

        @Override
        public byte[] getBytes() {
            return content;
        }

        @Override
        public InputStream getInputStream() {
            return new ByteArrayInputStream(content);
        }

        @Override
        public void transferTo(final File dest) throws IOException {
            java.nio.file.Files.write(dest.toPath(), content);
        }
    }
}
