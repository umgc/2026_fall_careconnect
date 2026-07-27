package com.careconnect.service.ai.ask;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.UserFile;
import com.careconnect.model.ai.ask.AskAiOcrOutbox;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.ai.ask.AskAiOcrOutboxRepository;
import com.careconnect.service.S3StorageService;
import com.careconnect.service.invoice.TextractService;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@ExtendWith(MockitoExtension.class)
class AskAiDocumentOcrServiceTest {

    @Mock private UserFileRepository userFileRepository;
    @Mock private AskAiOcrOutboxRepository ocrOutboxRepository;
    @Mock private IndexingEventEmitter indexingEventEmitter;
    @Mock private TextractService textractService;
    @Mock private S3StorageService s3StorageService;
    @Mock private AskAiDocumentOcrService selfProxy;

    private AskAiDocumentOcrService service;
    private UserFile userFile;

    @BeforeEach
    void setUp() {
        service = new AskAiDocumentOcrService(
                userFileRepository,
                ocrOutboxRepository,
                indexingEventEmitter,
                textractService,
                s3StorageService,
                selfProxy);
        userFile = UserFile.builder()
                .id(10L)
                .originalFilename("scan.pdf")
                .contentType("application/pdf")
                .patientId(1L)
                .fileCategory(UserFile.FileCategory.MEDICAL_RECORD)
                .storageType(UserFile.StorageType.DATABASE)
                .fileData(new byte[] {1, 2, 3, 4})
                .build();
    }

    @Test
    @DisplayName("isOcrCandidate - images and PDFs qualify")
    void isOcrCandidate_imagesAndPdfs() {
        assertTrue(AskAiDocumentOcrService.isOcrCandidate("image/png", "scan.png"));
        assertTrue(AskAiDocumentOcrService.isOcrCandidate("application/pdf", "scan.pdf"));
        assertTrue(AskAiDocumentOcrService.isOcrCandidate(null, "photo.JPEG"));
        assertFalse(AskAiDocumentOcrService.isOcrCandidate("text/plain", "notes.txt"));
        assertFalse(AskAiDocumentOcrService.isOcrCandidate(null, null));
    }

    @Test
    @DisplayName("enqueueAfterFailedExtract - upserts outbox then schedules async OCR")
    void enqueueAfterFailedExtract_schedulesAsync() {
        assertFalse(TransactionSynchronizationManager.isSynchronizationActive());
        service.enqueueAfterFailedExtract(userFile);
        verify(selfProxy).upsertPendingOutbox(10L);
        verify(selfProxy).processUploadedDocumentAsync(10L);
    }

    @Test
    @DisplayName("enqueueAfterFailedExtract - skips non-OCR candidates")
    void enqueueAfterFailedExtract_skipsNonCandidates() {
        userFile.setContentType("text/plain");
        userFile.setOriginalFilename("notes.txt");
        service.enqueueAfterFailedExtract(userFile);
        service.enqueueAfterFailedExtract(null);

        final AskAiDocumentOcrService noTextract = new AskAiDocumentOcrService(
                userFileRepository,
                ocrOutboxRepository,
                indexingEventEmitter,
                null,
                s3StorageService,
                selfProxy);
        userFile.setContentType("application/pdf");
        noTextract.enqueueAfterFailedExtract(userFile);

        verify(selfProxy, never()).processUploadedDocumentAsync(any());
        verify(selfProxy, never()).upsertPendingOutbox(any());
    }

    @Test
    @DisplayName("upsertPendingOutbox - creates PENDING row")
    void upsertPendingOutbox_createsRow() {
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.empty());
        when(ocrOutboxRepository.save(any(AskAiOcrOutbox.class))).thenAnswer(inv -> inv.getArgument(0));

        service.upsertPendingOutbox(10L);

        final ArgumentCaptor<AskAiOcrOutbox> captor = ArgumentCaptor.forClass(AskAiOcrOutbox.class);
        verify(ocrOutboxRepository).save(captor.capture());
        assertEquals(AskAiOcrOutbox.STATUS_PENDING, captor.getValue().getStatus());
        assertEquals(10L, captor.getValue().getFileId());
    }

    @Test
    @DisplayName("processUploadedDocumentAsync - delegates through proxy for @Transactional")
    void processUploadedDocumentAsync_usesProxy() {
        service.processUploadedDocumentAsync(10L);
        verify(selfProxy).processUploadedDocument(10L);
    }

    @Test
    @DisplayName("sweepPendingOcrJobs - requeues retryable outbox rows")
    void sweepPendingOcrJobs_requeues() {
        final AskAiOcrOutbox row = AskAiOcrOutbox.builder()
                .id(1L)
                .fileId(10L)
                .status(AskAiOcrOutbox.STATUS_PENDING)
                .attempts(1)
                .updatedAt(Instant.now().minusSeconds(60))
                .build();
        when(ocrOutboxRepository.findRetryable(anyInt(), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(row));

        service.sweepPendingOcrJobs();

        verify(selfProxy).processUploadedDocumentAsync(10L);
    }

    @Test
    @DisplayName("processUploadedDocument - persists OCR text from DB bytes and emits index event")
    void processUploadedDocument_persistsAndIndexes() throws Exception {
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.of(AskAiOcrOutbox.builder()
                .fileId(10L)
                .status(AskAiOcrOutbox.STATUS_PENDING)
                .attempts(0)
                .build()));
        when(ocrOutboxRepository.save(any(AskAiOcrOutbox.class))).thenAnswer(inv -> inv.getArgument(0));
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));
        when(textractService.analyzeAndGetResult(anyList(), eq("ask-ai-docs/")))
                .thenReturn(new com.careconnect.dto.chat.AiRequest.AnalysisResult(
                        "Patient continues metformin 500mg.", "ask-ai-docs/x.pdf"));

        service.processUploadedDocument(10L);

        final ArgumentCaptor<UserFile> saved = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(saved.capture());
        assertTrue(saved.getValue().getExtractedText().contains("metformin"));
        verify(indexingEventEmitter).emitDocumentIndexed(any());
    }

    @Test
    @DisplayName("processUploadedDocument - loads S3 bytes when not in DB")
    void processUploadedDocument_loadsFromS3() throws Exception {
        userFile.setStorageType(UserFile.StorageType.S3);
        userFile.setFileData(null);
        userFile.setS3Path("ask-ai-docs/scan.pdf");
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.empty());
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));
        when(s3StorageService.download("ask-ai-docs/scan.pdf")).thenReturn(new byte[] {9, 9});
        when(textractService.analyzeAndGetResult(anyList(), eq("ask-ai-docs/")))
                .thenReturn(new com.careconnect.dto.chat.AiRequest.AnalysisResult(
                        "S3 OCR text", "ask-ai-docs/x.pdf"));

        service.processUploadedDocument(10L);

        verify(s3StorageService).download("ask-ai-docs/scan.pdf");
        verify(userFileRepository).save(any(UserFile.class));
    }

    @Test
    @DisplayName("processUploadedDocument - blank OCR result skips persist")
    void processUploadedDocument_blankResult() throws Exception {
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.empty());
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(textractService.analyzeAndGetResult(anyList(), eq("ask-ai-docs/")))
                .thenReturn(new com.careconnect.dto.chat.AiRequest.AnalysisResult("   ", "ask-ai-docs/x.pdf"));

        service.processUploadedDocument(10L);

        verify(userFileRepository, never()).save(any());
        assertNull(userFile.getExtractedText());
    }

    @Test
    @DisplayName("processUploadedDocument - truncates oversized OCR text")
    void processUploadedDocument_truncates() throws Exception {
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.empty());
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(userFileRepository.save(any(UserFile.class))).thenAnswer(inv -> inv.getArgument(0));
        when(textractService.analyzeAndGetResult(anyList(), eq("ask-ai-docs/")))
                .thenReturn(new com.careconnect.dto.chat.AiRequest.AnalysisResult(
                        "Z".repeat(50_001), "ask-ai-docs/x.pdf"));

        service.processUploadedDocument(10L);

        final ArgumentCaptor<UserFile> saved = ArgumentCaptor.forClass(UserFile.class);
        verify(userFileRepository).save(saved.capture());
        assertTrue(saved.getValue().getExtractedText().contains("[OCR text truncated]"));
    }

    @Test
    @DisplayName("processUploadedDocument - Textract failures mark outbox failed")
    void processUploadedDocument_textractThrows() throws Exception {
        final AskAiOcrOutbox outbox = AskAiOcrOutbox.builder()
                .fileId(10L)
                .status(AskAiOcrOutbox.STATUS_PENDING)
                .attempts(0)
                .build();
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.of(outbox));
        when(ocrOutboxRepository.save(any(AskAiOcrOutbox.class))).thenAnswer(inv -> inv.getArgument(0));
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(textractService.analyzeAndGetResult(anyList(), eq("ask-ai-docs/")))
                .thenThrow(new RuntimeException("textract down"));

        service.processUploadedDocument(10L);

        verify(userFileRepository, never()).save(any(UserFile.class));
        assertEquals(AskAiOcrOutbox.STATUS_FAILED, outbox.getStatus());
    }

    @Test
    @DisplayName("upsertPendingOutbox - reopens COMPLETED and FAILED rows")
    void upsertPendingOutbox_reopensTerminalRows() {
        final AskAiOcrOutbox completed = AskAiOcrOutbox.builder()
                .fileId(10L)
                .status(AskAiOcrOutbox.STATUS_COMPLETED)
                .attempts(3)
                .lastError("old")
                .build();
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.of(completed));
        when(ocrOutboxRepository.save(any(AskAiOcrOutbox.class))).thenAnswer(inv -> inv.getArgument(0));

        service.upsertPendingOutbox(10L);
        assertEquals(AskAiOcrOutbox.STATUS_PENDING, completed.getStatus());
        assertEquals(0, completed.getAttempts());
        assertNull(completed.getLastError());

        final AskAiOcrOutbox failed = AskAiOcrOutbox.builder()
                .fileId(11L)
                .status(AskAiOcrOutbox.STATUS_FAILED)
                .attempts(2)
                .build();
        when(ocrOutboxRepository.findByFileId(11L)).thenReturn(Optional.of(failed));
        service.upsertPendingOutbox(11L);
        assertEquals(AskAiOcrOutbox.STATUS_PENDING, failed.getStatus());
    }

    @Test
    @DisplayName("processUploadedDocumentAsync - marks outbox failed when proxy throws")
    void processUploadedDocumentAsync_marksFailedOnThrow() {
        org.mockito.Mockito.doThrow(new RuntimeException("boom"))
                .when(selfProxy)
                .processUploadedDocument(10L);

        service.processUploadedDocumentAsync(10L);

        verify(selfProxy).markOutboxFailed(eq(10L), eq("boom"));
    }

    @Test
    @DisplayName("processUploadedDocument - missing file completes outbox")
    void processUploadedDocument_missingFileCompletesOutbox() {
        when(ocrOutboxRepository.findByFileId(10L)).thenReturn(Optional.of(AskAiOcrOutbox.builder()
                .fileId(10L)
                .status(AskAiOcrOutbox.STATUS_PENDING)
                .attempts(0)
                .build()));
        when(ocrOutboxRepository.save(any(AskAiOcrOutbox.class))).thenAnswer(inv -> inv.getArgument(0));
        when(userFileRepository.findById(10L)).thenReturn(Optional.empty());

        service.processUploadedDocument(10L);

        verify(userFileRepository, never()).save(any(UserFile.class));
        verify(indexingEventEmitter, never()).emitDocumentIndexed(any());
    }

    @Test
    @DisplayName("sweepPendingOcrJobs - no-op without Textract")
    void sweepPendingOcrJobs_noopWithoutTextract() {
        final AskAiDocumentOcrService noTextract = new AskAiDocumentOcrService(
                userFileRepository,
                ocrOutboxRepository,
                indexingEventEmitter,
                null,
                s3StorageService,
                selfProxy);
        noTextract.sweepPendingOcrJobs();
        verify(ocrOutboxRepository, never()).findRetryable(anyInt(), any(Instant.class), any(Pageable.class));
    }

    @Test
    @DisplayName("InMemoryMultipartFile exposes bytes and metadata")
    void inMemoryMultipartFile_exposesContent() throws Exception {
        final byte[] bytes = new byte[] {9, 8, 7};
        final AskAiDocumentOcrService.InMemoryMultipartFile file =
                new AskAiDocumentOcrService.InMemoryMultipartFile(
                        "file", "scan.png", "image/png", bytes);
        assertEquals("file", file.getName());
        assertEquals("scan.png", file.getOriginalFilename());
        assertEquals("image/png", file.getContentType());
        assertFalse(file.isEmpty());
        assertEquals(3, file.getSize());
        assertArrayEquals(bytes, file.getBytes());
        assertEquals(3, file.getInputStream().readAllBytes().length);

        final AskAiDocumentOcrService.InMemoryMultipartFile empty =
                new AskAiDocumentOcrService.InMemoryMultipartFile("f", "x.bin", null, null);
        assertTrue(empty.isEmpty());
        assertEquals(0, empty.getSize());

        final java.io.File dest = java.io.File.createTempFile("ocr-transfer", ".bin");
        dest.deleteOnExit();
        file.transferTo(dest);
        assertEquals(3, dest.length());
    }
}
