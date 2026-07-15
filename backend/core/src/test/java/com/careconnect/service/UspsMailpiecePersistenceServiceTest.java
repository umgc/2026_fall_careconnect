package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.MailpieceIndexedPayload;
import com.careconnect.model.MailPiece;
import com.careconnect.model.Patient;
import com.careconnect.model.USPSDigest;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UspsMailpiecePersistenceServiceTest {

    @Mock private PatientRepository patientRepository;
    @Mock private UspsMailpieceRepository mailpieceRepository;
    @Mock private IndexingEventEmitter indexingEventEmitter;

    private UspsMailpiecePersistenceService service;
    private final AtomicLong idSeq = new AtomicLong(100);

    @BeforeEach
    void setUp() {
        service = new UspsMailpiecePersistenceService(
                patientRepository,
                mailpieceRepository,
                new MailpieceNormalizer(),
                indexingEventEmitter);
    }

    @Test
    @DisplayName("persistAndIndex skips when userId is non-numeric")
    void persistAndIndex_skipsNonNumericUserId() {
        final USPSDigest digest = digestWithOnePiece();

        assertThat(service.persistAndIndex("demo-user", digest)).isZero();
        verify(mailpieceRepository, never()).save(any());
        verify(indexingEventEmitter, never()).emitMailpieceIndexed(any());
    }

    @Test
    @DisplayName("persistAndIndex skips when patient is not found")
    void persistAndIndex_skipsMissingPatient() {
        when(patientRepository.findByUserId(9L)).thenReturn(Optional.empty());

        assertThat(service.persistAndIndex("9", digestWithOnePiece())).isZero();
        verify(mailpieceRepository, never()).save(any());
    }

    @Test
    @DisplayName("persistAndIndex upserts and emits MAILPIECE_INDEXED for new rows")
    void persistAndIndex_upsertsAndEmits() {
        final Patient patient = new Patient();
        patient.setId(42L);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(mailpieceRepository.findByPatientIdAndSourceKey(any(), any()))
                .thenReturn(Optional.empty());
        when(mailpieceRepository.save(any(UspsMailpiece.class))).thenAnswer(inv -> {
            final UspsMailpiece entity = inv.getArgument(0);
            if (entity.getId() == null) {
                entity.setId(idSeq.getAndIncrement());
            }
            return entity;
        });
        when(indexingEventEmitter.emitMailpieceIndexed(any()))
                .thenReturn(IndexingOutboxRow.builder().id(1L).build());

        final int upserted = service.persistAndIndex("7", digestWithOnePiece());

        assertThat(upserted).isEqualTo(1);
        final ArgumentCaptor<MailpieceIndexedPayload> payloadCaptor =
                ArgumentCaptor.forClass(MailpieceIndexedPayload.class);
        verify(indexingEventEmitter).emitMailpieceIndexed(payloadCaptor.capture());
        assertThat(payloadCaptor.getValue().patientId()).isEqualTo(42L);
        assertThat(payloadCaptor.getValue().mailpieceId()).isNotNull();
        assertThat(payloadCaptor.getValue().contentHash()).isNotBlank();
    }

    @Test
    @DisplayName("persistAndIndex does not emit when content_hash is unchanged")
    void persistAndIndex_noEmitWhenHashUnchanged() {
        final Patient patient = new Patient();
        patient.setId(42L);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));

        final USPSDigest digest = digestWithOnePiece();
        final MailpieceNormalizer.NormalizedMailpiece normalized =
                new MailpieceNormalizer().normalize(digest.mailpieces().get(0), digest.digestDate());

        final UspsMailpiece existing = new UspsMailpiece();
        existing.setId(55L);
        existing.setPatientId(42L);
        existing.setSourceKey(normalized.sourceKey());
        existing.setContentHash(normalized.contentHash());
        when(mailpieceRepository.findByPatientIdAndSourceKey(42L, normalized.sourceKey()))
                .thenReturn(Optional.of(existing));
        when(mailpieceRepository.save(any(UspsMailpiece.class))).thenAnswer(inv -> inv.getArgument(0));

        assertThat(service.persistAndIndex("7", digest)).isEqualTo(1);
        verify(indexingEventEmitter, never()).emitMailpieceIndexed(any());
        verify(mailpieceRepository, times(1)).save(any());
    }

    private static USPSDigest digestWithOnePiece() {
        final OffsetDateTime now = OffsetDateTime.of(2025, 3, 3, 12, 0, 0, 0, ZoneOffset.UTC);
        final MailPiece piece = new MailPiece(
                "m-1", "Acme Bank", "Statement",
                "https://example.com/x.png", now, null);
        return new USPSDigest(now, List.of(piece), List.of());
    }
}
