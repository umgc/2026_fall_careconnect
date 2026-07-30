package com.careconnect.service;

import com.careconnect.model.MailPiece;
import com.careconnect.model.Patient;
import com.careconnect.model.USPSDigest;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.service.mail.MailpieceImportanceClassifier;
import com.careconnect.service.mail.MailpieceImportanceResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Normalizes, upserts, classifies importance, and queues indexing for USPS
 * mailpieces (Tasks 3.14.5 / #122, 3.14.6 / #123).
 */
@Service
public class UspsMailpiecePersistenceService {

    private static final Logger log = LoggerFactory.getLogger(UspsMailpiecePersistenceService.class);

    private final PatientRepository patientRepository;
    private final UspsMailpieceRepository mailpieceRepository;
    private final MailpieceNormalizer normalizer;
    private final MailpieceImportanceClassifier importanceClassifier;
    private final UspsMailpieceAtomicPersistenceService atomicPersistenceService;

    public UspsMailpiecePersistenceService(
            final PatientRepository patientRepository,
            final UspsMailpieceRepository mailpieceRepository,
            final MailpieceNormalizer normalizer,
            final MailpieceImportanceClassifier importanceClassifier,
            final UspsMailpieceAtomicPersistenceService atomicPersistenceService) {
        this.patientRepository = patientRepository;
        this.mailpieceRepository = mailpieceRepository;
        this.normalizer = normalizer;
        this.importanceClassifier = importanceClassifier;
        this.atomicPersistenceService = atomicPersistenceService;
    }

    /**
     * Persist each mailpiece in {@code digest} for the patient linked to {@code userId}.
     * Skips when {@code userId} is non-numeric or no Patient row exists.
     *
     * @return number of mailpieces upserted (including no-op hash matches)
     */
    public int persistAndIndex(final String userId, final USPSDigest digest) {
        if (digest == null || digest.mailpieces() == null || digest.mailpieces().isEmpty()) {
            return 0;
        }
        final Long patientId = resolvePatientId(userId);
        if (patientId == null) {
            log.warn("Skipping USPS mailpiece persistence — no patient for userId={}", userId);
            return 0;
        }

        int upserted = 0;
        for (final MailPiece piece : digest.mailpieces()) {
            if (piece == null) {
                continue;
            }
            final MailpieceNormalizer.NormalizedMailpiece normalized =
                    normalizer.normalize(piece, digest.digestDate());
            final String persistedOcrText = mailpieceRepository
                    .findByPatientIdAndSourceKey(patientId, normalized.sourceKey())
                    .map(UspsMailpiece::getOcrText)
                    .orElse(null);
            final MailpieceImportanceResult classification =
                    importanceClassifier == null
                            ? null
                            : importanceClassifier.classify(
                                    normalized.sender(), normalized.summary(), persistedOcrText);
            atomicPersistenceService.persist(
                    patientId, userId, normalized, classification);
            upserted++;
        }
        log.info("USPS mailpiece persistence upserted={} patientId={} userId={}",
                upserted, patientId, userId);
        return upserted;
    }

    Long resolvePatientId(final String userId) {
        if (userId == null || userId.isBlank()) {
            return null;
        }
        final String trimmed = userId.trim();
        try {
            final long userPk = Long.parseLong(trimmed);
            return patientRepository.findByUserId(userPk).map(Patient::getId).orElse(null);
        } catch (final NumberFormatException ex) {
            return null;
        }
    }

    static void applyNormalized(
            final UspsMailpiece entity,
            final Long patientId,
            final String userId,
            final MailpieceNormalizer.NormalizedMailpiece normalized) {
        entity.setPatientId(patientId);
        entity.setUserId(userId);
        entity.setSourceKey(normalized.sourceKey());
        entity.setExternalId(normalized.externalId());
        entity.setSender(normalized.sender());
        entity.setSummary(normalized.summary());
        entity.setImageRef(normalized.imageRef());
        entity.setReceivedAt(normalized.receivedAt());
        entity.setDigestDate(normalized.digestDate());
        entity.setContentHash(normalized.contentHash());
        entity.setConsentScope(normalized.consentScope());
    }

    static void applyImportance(
            final UspsMailpiece entity,
            final MailpieceImportanceResult result) {
        if (result == null) {
            return;
        }
        entity.setImportanceLevel(result.level() == null ? null : result.level().name());
        entity.setImportanceConfidence(result.confidence());
        entity.setClassificationMethod(result.method());
        entity.setClassificationEngine(result.engine());
        entity.setImportanceReasoning(result.reasoning());
        entity.setImportanceCategory(result.category());
        entity.setClassifiedAt(result.classifiedAt());
    }
}
