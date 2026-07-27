package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.MailpieceIndexedPayload;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.service.mail.MailpieceImportanceResult;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Owns the short lock/recheck/save/outbox phase of USPS persistence. */
@Service
@RequiredArgsConstructor
public class UspsMailpieceAtomicPersistenceService {

  private final UspsMailpieceRepository mailpieceRepository;
  private final IndexingEventEmitter indexingEventEmitter;

  @Transactional
  public UspsMailpiece persist(
      final Long patientId,
      final String userId,
      final MailpieceNormalizer.NormalizedMailpiece normalized,
      final MailpieceImportanceResult classification) {
    mailpieceRepository.acquirePersistenceLock(
        "usps-mailpiece:" + patientId + ":" + normalized.sourceKey());
    final UspsMailpiece entity =
        mailpieceRepository
            .findByPatientIdAndSourceKey(patientId, normalized.sourceKey())
            .orElseGet(UspsMailpiece::new);
    final boolean isNew = entity.getId() == null;
    final boolean hashChanged =
        isNew
            || entity.getContentHash() == null
            || !entity.getContentHash().equals(normalized.contentHash());
    final boolean needsClassification =
        hashChanged || entity.getImportanceLevel() == null || entity.getImportanceLevel().isBlank();

    UspsMailpiecePersistenceService.applyNormalized(entity, patientId, userId, normalized);
    if (needsClassification) {
      UspsMailpiecePersistenceService.applyImportance(entity, classification);
    }
    final UspsMailpiece saved = mailpieceRepository.save(entity);
    if (hashChanged || needsClassification) {
      indexingEventEmitter.emitMailpieceIndexed(
          new MailpieceIndexedPayload(
              saved.getId(),
              patientId,
              saved.getSourceKey(),
              saved.getContentHash(),
              saved.getSender(),
              saved.getSummary(),
              saved.getDigestDate(),
              saved.getConsentScope()));
    }
    return saved;
  }
}
