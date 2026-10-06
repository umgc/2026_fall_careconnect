package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.dto.ehr.AthenaConnectionResponse;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.Patient;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.service.ConsentService;
import com.careconnect.service.ehr.EhrAuditService;
import com.careconnect.service.ehr.EhrSourceDataPurger;
import com.careconnect.service.ehr.EhrSourceResolver;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;

/**
 * Connection lifecycle for athenahealth: status, connect, disconnect.
 *
 * <p>A user is connected when they hold an active EHR-import consent grant AND their patient profile
 * is linked to an athena chart. Both are required because with 2-legged OAuth athena authorizes the
 * application, not the patient: the application could read any chart in the practice, so the
 * patient's in-app consent is the only authorization this access has.
 */
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.athena.enabled", havingValue = "true")
public class AthenaConnectionService {

    static final String NOT_CONSENTED = "NOT_CONSENTED";
    static final String NOT_LINKED = "NOT_LINKED";

    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;

    private final ConsentService consentService;
    private final ConsentGrantRepository consentGrants;
    private final AthenaPatientLinker linker;
    private final AthenaSyncService syncService;
    private final AthenaFhirClient fhir;
    private final EhrSourceDataPurger purger;
    private final EhrSourceResolver sources;
    private final PatientRepository patients;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrAuditService audit;
    private final TransactionTemplate transactionTemplate;

    public AthenaConnectionResponse status(final Long userId) {
        if (!hasConsent(userId)) {
            return AthenaConnectionResponse.notConnected(NOT_CONSENTED);
        }
        if (fhir.linkedPatientId(userId).isEmpty()) {
            return AthenaConnectionResponse.notConnected(NOT_LINKED);
        }
        return AthenaConnectionResponse.connected(null);
    }

    public boolean isConnected(final Long userId) {
        return hasConsent(userId) && fhir.linkedPatientId(userId).isPresent();
    }

    /**
     * Record the patient's consent, link their athena chart, and run the first sync.
     *
     * <p>Consent is recorded first because finding the chart is itself a search across the practice.
     * A failed link keeps the consent, so the patient can correct their profile and try again.
     *
     * @throws AthenaSyncInProgressException if a sync for this user is already running
     */
    public AthenaConnectionResponse connect(final Long userId) {
        consentService.recordEhrImportConsent(userId);
        final AthenaLinkResult link = linker.link(userId);
        if (!link.isLinked()) {
            return AthenaConnectionResponse.notConnected(link.state().name());
        }
        return AthenaConnectionResponse.connected(syncService.sync(userId));
    }

    /**
     * Unlink athena and delete its data for this user, per the A1-Q1 unlink rule
     * ({@link EhrSourceDataPurger}). Returns only after the deletes have committed.
     */
    public EhrSourceDataPurger.Purged disconnect(final Long userId) {
        final EhrSourceDataPurger.Purged purged = transactionTemplate.execute(tx -> {
            final Long patientId = patients.findByUserId(userId).map(Patient::getId).orElse(null);
            final EhrSourceDataPurger.Purged removed =
                    purger.purge(userId, patientId, sources.idForCode(SOURCE), SOURCE);
            // EHR_IMPORT is a single grant shared by every EHR source, so revoking it while another
            // source is still linked would cut that source off too. Revoke only with the last link.
            if (patientId == null || crosswalks.findByPatientId(patientId).isEmpty()) {
                consentService.revokeEhrImportConsent(userId);
            }
            return removed;
        });
        audit.record(userId, SOURCE, "ATHENA_DISCONNECT", EhrAuditService.OUTCOME_OK);
        return purged;
    }

    private boolean hasConsent(final Long userId) {
        return !consentGrants.findActiveGrants(
                userId, userId, ConsentGrant.SCOPE_EHR_IMPORT, Instant.now()).isEmpty();
    }
}
