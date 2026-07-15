package com.careconnect.service;

import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.indexing.MailpieceIndexedPayload;
import com.careconnect.model.MailPiece;
import com.careconnect.model.Patient;
import com.careconnect.model.USPSDigest;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Normalizes, upserts, and queues indexing for USPS mailpieces (Task 3.14.5 / #122).
 */
@Service
public class UspsMailpiecePersistenceService {

    private static final Logger log = LoggerFactory.getLogger(UspsMailpiecePersistenceService.class);

    private final PatientRepository patientRepository;
    private final UspsMailpieceRepository mailpieceRepository;
    private final MailpieceNormalizer normalizer;
    private final IndexingEventEmitter indexingEventEmitter;

    public UspsMailpiecePersistenceService(
            final PatientRepository patientRepository,
            final UspsMailpieceRepository mailpieceRepository,
            final MailpieceNormalizer normalizer,
            final IndexingEventEmitter indexingEventEmitter) {
        this.patientRepository = patientRepository;
        this.mailpieceRepository = mailpieceRepository;
        this.normalizer = normalizer;
        this.indexingEventEmitter = indexingEventEmitter;
    }

    /**
     * Persist each mailpiece in {@code digest} for the patient linked to {@code userId}.
     * Skips when {@code userId} is non-numeric or no Patient row exists.
     *
     * @return number of mailpieces upserted (including no-op hash matches)
     */
    @Transactional
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
            final UspsMailpiece entity = mailpieceRepository
                    .findByPatientIdAndSourceKey(patientId, normalized.sourceKey())
                    .orElseGet(UspsMailpiece::new);

            final boolean isNew = entity.getId() == null;
            final boolean hashChanged = isNew
                    || entity.getContentHash() == null
                    || !entity.getContentHash().equals(normalized.contentHash());

            applyNormalized(entity, patientId, userId, normalized);
            final UspsMailpiece saved = mailpieceRepository.save(entity);
            upserted++;

            if (hashChanged) {
                indexingEventEmitter.emitMailpieceIndexed(new MailpieceIndexedPayload(
                        saved.getId(),
                        patientId,
                        saved.getSourceKey(),
                        saved.getContentHash(),
                        saved.getSender(),
                        saved.getSummary(),
                        saved.getDigestDate(),
                        saved.getConsentScope()));
            }
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

    private static void applyNormalized(
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
}
