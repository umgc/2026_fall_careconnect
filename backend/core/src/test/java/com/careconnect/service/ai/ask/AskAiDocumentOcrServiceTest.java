package com.careconnect.service.ai.ask;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.UserFile;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.service.S3StorageService;
import com.careconnect.service.invoice.TextractService;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@ExtendWith(MockitoExtension.class)
class AskAiDocumentOcrServiceTest {

    @Mock private UserFileRepository userFileRepository;
    @Mock private IndexingEventEmitter indexingEventEmitter;
    @Mock private TextractService textractService;
    @Mock private S3StorageService s3StorageService;
    @Mock private AskAiDocumentOcrService selfProxy;

    private AskAiDocumentOcrService service;
    private UserFile userFile;

    @BeforeEach
    void setUp() {
        service = new AskAiDocumentOcrService(
                userFileRepository, indexingEventEmitter, textractService, s3StorageService, selfProxy);
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
    @DisplayName("enqueueAfterFailedExtract - schedules async OCR via Spring proxy when no txn")
    void enqueueAfterFailedExtract_schedulesAsync() {
        assertFalse(TransactionSynchronizationManager.isSynchronizationActive());
        service.enqueueAfterFailedExtract(userFile);
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
                userFileRepository, indexingEventEmitter, null, s3StorageService, selfProxy);
        userFile.setContentType("application/pdf");
        noTextract.enqueueAfterFailedExtract(userFile);

        verify(selfProxy, never()).processUploadedDocumentAsync(any());
    }

    @Test
    @DisplayName("processUploadedDocument - persists OCR text from DB bytes and emits index event")
    void processUploadedDocument_persistsAndIndexes() throws Exception {
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
    @DisplayName("processUploadedDocument - Textract failures are swallowed")
    void processUploadedDocument_textractThrows() throws Exception {
        when(userFileRepository.findById(10L)).thenReturn(Optional.of(userFile));
        when(textractService.analyzeAndGetResult(anyList(), eq("ask-ai-docs/")))
                .thenThrow(new RuntimeException("textract down"));

        service.processUploadedDocument(10L);

        verify(userFileRepository, never()).save(any());
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
