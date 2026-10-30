package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.ClinicalNoteIndexedPayload;
import com.careconnect.indexing.DocumentIndexedPayload;
import com.careconnect.indexing.EpicFhirIndexedPayload;
import com.careconnect.indexing.IndexingEventType;
import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class IndexWorkerDispatchCoverageTest {

    private final ObjectMapper mapper = new ObjectMapper();
    private IndexingOutboxRepository outbox;
    private RetrievalIndexService indexService;
    private IndexWorker worker;

    @BeforeEach
    void setUp() {
        outbox = mock(IndexingOutboxRepository.class);
        indexService = mock(RetrievalIndexService.class);
        worker = new IndexWorker(outbox, indexService, mapper, new NoOpTransactionManager(), 10, 3, 2, 6);
    }

    private IndexingOutboxRow row(long id, String eventType, String json) {
        return IndexingOutboxRow.builder().id(id).eventType(eventType).payloadJson(json).attemptCount(0).build();
    }

    private String envelope(String eventType, Object payload) throws Exception {
        return mapper.writeValueAsString(Map.of("eventType", eventType, "payload", payload));
    }

    @Test
    void dispatchesNoteDocumentAndEpicEvents() throws Exception {
        when(indexService.ingestClinicalNoteIndexed(any())).thenReturn(1);
        when(indexService.ingestDocumentIndexed(any())).thenReturn(2);
        when(indexService.ingestEpicFhir(any())).thenReturn(3);
        worker.processRow(row(1L, IndexingEventType.CLINICAL_NOTE_INDEXED, envelope(
                IndexingEventType.CLINICAL_NOTE_INDEXED, new ClinicalNoteIndexedPayload(5L, 9L, "h", "on_consent"))));
        worker.processRow(row(2L, IndexingEventType.DOCUMENT_INDEXED, envelope(
                IndexingEventType.DOCUMENT_INDEXED, new DocumentIndexedPayload(6L, 9L, "h", "OTHER", "t", "c"))));
        worker.processRow(row(3L, IndexingEventType.EPIC_FHIR_INDEXED, envelope(
                IndexingEventType.EPIC_FHIR_INDEXED, new EpicFhirIndexedPayload(7L, 9L, "h", "c"))));
        verify(indexService).ingestClinicalNoteIndexed(any());
        verify(indexService).ingestDocumentIndexed(any());
        verify(indexService).ingestEpicFhir(any());
    }

    @Test
    void handlesUnsupportedMalformedAndFailingRows() throws Exception {
        worker.processRow(null);
        worker.processRow(row(4L, "SOMETHING_ELSE", envelope("SOMETHING_ELSE", Map.of("x", 1))));
        worker.processRow(row(5L, IndexingEventType.DOCUMENT_INDEXED, "{not json"));
        worker.processRow(row(6L, IndexingEventType.DOCUMENT_INDEXED, "{\"eventType\":\"DOCUMENT_INDEXED\"}"));
        when(indexService.ingestEpicFhir(any())).thenThrow(new RuntimeException("db", new IllegalStateException("root")));
        IndexingOutboxRow failing = row(7L, IndexingEventType.EPIC_FHIR_INDEXED, envelope(
                IndexingEventType.EPIC_FHIR_INDEXED, new EpicFhirIndexedPayload(7L, 9L, "h", "c")));
        worker.processRow(failing);
        assertThat(failing.getLastError()).isNotBlank();
    }

    private static final class NoOpTransactionManager implements PlatformTransactionManager {
        @Override
        public TransactionStatus getTransaction(TransactionDefinition definition) {
            return new SimpleTransactionStatus();
        }

        @Override
        public void commit(TransactionStatus status) {
            // no-op
        }

        @Override
        public void rollback(TransactionStatus status) {
            // no-op
        }
    }
}
