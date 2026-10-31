package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.StructuredDocumentEntry;
import com.careconnect.model.UserFile;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.StructuredDocumentEntryRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ai.ask.AskAiDocumentOcrService;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class FileManagementServiceCoverageTest {

    @Mock private UserFileRepository userFileRepository;
    @Mock private StructuredDocumentEntryRepository structuredEntryRepository;
    @Mock private UserRepository userRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private DatabaseStorageService databaseStorageService;
    @Mock private DocumentComplianceService documentComplianceService;
    @Mock private IndexingEventEmitter indexingEventEmitter;
    @Mock private RetrievalIndexService retrievalIndexService;
    @Mock private DocumentProcessingService documentProcessingService;
    @Mock private S3StorageService s3StorageService;
    @Mock private AskAiDocumentOcrService askAiDocumentOcrService;

    private FileManagementService service;

    @BeforeEach
    void setUp() {
        service = new FileManagementService(userFileRepository, structuredEntryRepository, userRepository,
                patientRepository, databaseStorageService, documentComplianceService, indexingEventEmitter,
                retrievalIndexService, documentProcessingService, s3StorageService, askAiDocumentOcrService);
    }

    private static UserFile file(Long id) {
        return UserFile.builder().id(id).filename("f" + id).originalFilename("f.pdf").contentType("application/pdf")
                .fileSize(3L).ownerId(1L).ownerType(UserFile.OwnerType.CAREGIVER)
                .fileCategory(UserFile.FileCategory.ONBOARDING_FORM).patientId(4L)
                .storageType(UserFile.StorageType.DATABASE).description("Onboarding PDF").isActive(true).build();
    }

    @Test
    void storeGeneratedDocumentPersistsAndEmitsIndexing() {
        when(userFileRepository.save(any())).thenAnswer(inv -> {
            UserFile f = inv.getArgument(0);
            f.setId(9L);
            return f;
        });
        UserFile saved = service.storeGeneratedDocument("pdf".getBytes(StandardCharsets.UTF_8), "copy.pdf",
                "application/pdf", 1L, UserFile.OwnerType.CAREGIVER, "ONBOARDING_FORM", "Submitted copy", 4L);
        assertThat(saved.getId()).isEqualTo(9L);
        verify(indexingEventEmitter).emitDocumentIndexed(any());

        doThrow(new RuntimeException("emit")).when(indexingEventEmitter).emitDocumentIndexed(any());
        assertThat(service.storeGeneratedDocument(new byte[]{1}, "x.pdf", "application/pdf", 1L,
                UserFile.OwnerType.CAREGIVER, "ONBOARDING_FORM", "desc", 4L)).isNotNull();
        assertThat(service.storeGeneratedDocument(new byte[]{1}, "x.pdf", "application/pdf", 1L,
                UserFile.OwnerType.CAREGIVER, "ONBOARDING_FORM", null, null)).isNotNull();
    }

    @Test
    void employmentDocumentListings() {
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(any(), any(), any()))
                .thenReturn(List.of(file(1L)));
        when(userFileRepository.findByPatientIdAndFileCategoryInAndIsActiveTrue(any(), any()))
                .thenReturn(List.of(file(2L)));
        assertThat(service.listEmploymentDocumentsForUser(1L, "caregiver")).hasSize(1);
        assertThat(service.listEmploymentDocumentsForPatient(4L)).hasSize(1);
    }

    @Test
    void structuredEntryLookups() {
        StructuredDocumentEntry entry = StructuredDocumentEntry.builder().id(5L).userFileId(1L)
                .documentType(UserFile.FileCategory.ONBOARDING_FORM).patientId(4L)
                .fieldsJson("{\"a\":\"b\"}").isActive(true).build();
        StructuredDocumentEntry badJson = StructuredDocumentEntry.builder().id(6L).userFileId(2L).documentType(UserFile.FileCategory.ONBOARDING_FORM)
                .fieldsJson("{not json").isActive(true).build();
        StructuredDocumentEntry orphan = StructuredDocumentEntry.builder().id(7L).userFileId(99L).documentType(UserFile.FileCategory.ONBOARDING_FORM)
                .fieldsJson(null).isActive(true).build();
        when(structuredEntryRepository.findById(5L)).thenReturn(Optional.of(entry));
        when(userFileRepository.findById(1L)).thenReturn(Optional.of(file(1L)));
        assertThat(service.getStructuredEntry(5L)).isPresent();

        when(structuredEntryRepository.findByPatientIdAndIsActiveTrue(4L)).thenReturn(List.of(entry, badJson, orphan));
        when(userFileRepository.findAllById(any())).thenReturn(List.of(file(1L), file(2L)));
        assertThat(service.listStructuredEntriesForPatient(4L)).hasSize(2);
    }
}
