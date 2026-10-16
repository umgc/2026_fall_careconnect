package com.careconnect.service.ehr;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrCoverageRecordRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.repository.ehr.EhrVisitRecordRepository;
import com.careconnect.security.TokenCryptor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.Objects;
import java.util.Optional;

/**
 * A patient's connection to their Medicare account: starting a link, finishing it when Blue Button
 * calls back, and reporting whether one exists (WBS 6.2.39; SRS FR-MCR-01…05).
 *
 * <h2>How a link carries the patient across the redirect</h2>
 * The browser that signs in at Medicare cannot present the CareConnect JWT: the app opens it as a
 * plain page, and on mobile it is a different application altogether. So the patient first asks
 * for a link while signed in ({@link #startLink}), which stores a one-time, short-lived link token
 * on their crosswalk row. The browser carries only that token; the callback swaps it back for the
 * patient ({@link #completeLink}). This is the same shape as the Gmail connect flow's start token.
 *
 * <h2>Identity</h2>
 * Everything here is keyed by {@code patient.id}, never the user id. {@code
 * ehr_patient_crosswalk.patient_id} is a foreign key to {@code patient}, and the two ids are
 * different numbers for most accounts (in the dev seed, patient 2 belongs to user 6).
 *
 * <h2>Unlinking</h2>
 * {@link #disconnect} follows SRS FR-MCR-11 as settled in Addendum A1-Q1 (2026-10-03): the patient's
 * Medicare data goes immediately, before the confirmation, and some things stay. See that method.
 *
 * <h2>Tokens</h2>
 * The access and refresh tokens are encrypted at rest with {@link TokenCryptor}, as the SRS data
 * dictionary requires, and are never returned to a client (NFR-SEC-03).
 */
@Slf4j
@Service
public class MedicareConnectionService {

    /** Source code in {@code ehr_source}, and the Spring OAuth client registration id. */
    public static final String MEDICARE = "MEDICARE";
    public static final String REGISTRATION_ID = "medicare";

    /** Long enough to sign in at Medicare.gov, short enough that a leaked link is soon useless. */
    static final Duration LINK_TOKEN_TTL = Duration.ofMinutes(15);

    /** Refresh this long before the access token's stated expiry, so a call never starts on a dying token. */
    static final Duration REFRESH_MARGIN = Duration.ofMinutes(1);

    /** ERR-MCR-05 (SRS §8.6): the text the patient sees when their Medicare link has lapsed. */
    public static final String ERR_MCR_05_MESSAGE =
            "Your Medicare connection has expired. Connect again to see current records.";

    /**
     * The patient has no working Medicare link: never linked, unlinked, or the token was rejected
     * (FR-MCR-09). Answered with ERR-MCR-05 by {@code MedicareErrorAdvice}.
     */
    public static class MedicareNotConnectedException extends RuntimeException {
        public MedicareNotConnectedException() {
            super(ERR_MCR_05_MESSAGE);
        }
    }

    private static final SecureRandom RANDOM = new SecureRandom();

    /** What happened to a link when Blue Button called back. Each value is also the code the
     *  frontend receives in its {@code ?medicare=} query parameter. */
    public enum LinkOutcome {
        CONNECTED("connected"),
        /** No pending link for that token, or it expired. The patient starts again. */
        LINK_EXPIRED("link_expired"),
        /** That Medicare account is already linked to a different CareConnect patient. */
        ALREADY_LINKED_ELSEWHERE("already_linked");

        private final String code;

        LinkOutcome(final String code) {
            this.code = code;
        }

        public String code() {
            return code;
        }
    }

    /** The body of {@code GET /v1/api/medicare/status}, the shape the Medicare tile expects. */
    public record ConnectionStatus(boolean connected, String status, LocalDateTime connectedAt) {
        static ConnectionStatus unlinked() {
            return new ConnectionStatus(false, "UNLINKED", null);
        }
    }

    /** The Medicare data an unlink removes, one repository per table. */
    public record MedicareDataStores(
            EhrRawPayloadRepository rawPayloads,
            EhrSourceIdentityRepository sourceIdentities,
            EhrCoverageRecordRepository coverages,
            EhrVisitRecordRepository visits,
            EhrIdentityConflictRepository conflicts) {
    }

    private final PatientRepository patients;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrSourceRepository sources;
    private final TokenCryptor cryptor;
    private final MedicareService medicare;
    private final MedicareTokenRefresher refresher;
    private final MedicareDataStores stores;
    private final TransactionTemplate transactions;
    private final Clock clock;

    @Autowired
    public MedicareConnectionService(
            final PatientRepository patients,
            final EhrPatientCrosswalkRepository crosswalks,
            final EhrSourceRepository sources,
            final TokenCryptor cryptor,
            final MedicareService medicare,
            final MedicareTokenRefresher refresher,
            final EhrRawPayloadRepository rawPayloads,
            final EhrSourceIdentityRepository sourceIdentities,
            final EhrCoverageRecordRepository coverages,
            final EhrVisitRecordRepository visits,
            final EhrIdentityConflictRepository conflicts,
            final TransactionTemplate transactions) {
        this(patients, crosswalks, sources, cryptor, medicare, refresher,
                new MedicareDataStores(rawPayloads, sourceIdentities, coverages, visits, conflicts),
                transactions, Clock.systemUTC());
    }

    MedicareConnectionService(
            final PatientRepository patients,
            final EhrPatientCrosswalkRepository crosswalks,
            final EhrSourceRepository sources,
            final TokenCryptor cryptor,
            final MedicareService medicare,
            final MedicareTokenRefresher refresher,
            final MedicareDataStores stores,
            final TransactionTemplate transactions,
            final Clock clock) {
        this.patients = patients;
        this.crosswalks = crosswalks;
        this.sources = sources;
        this.cryptor = cryptor;
        this.medicare = medicare;
        this.refresher = refresher;
        this.stores = stores;
        this.transactions = transactions;
        this.clock = clock;
    }

    /** The {@code patient.id} for a signed-in user, or empty if they have no patient record. */
    public Optional<Long> patientIdFor(final User user) {
        if (user == null || user.getId() == null) {
            return Optional.empty();
        }
        return patients.findByUserId(user.getId()).map(Patient::getId);
    }

    /** {@code ehr_source.id} for Medicare. Seeded by {@code SchemaPatchRunner}, so always present. */
    public Long medicareSourceId() {
        return sources.findByCode(MEDICARE)
                .orElseThrow(() -> new IllegalStateException("ehr_source has no MEDICARE row"))
                .getId();
    }

    /** The patient's Medicare crosswalk row, linked or pending, if there is one. */
    public Optional<EhrPatientCrosswalk> crosswalkFor(final Long patientId) {
        return crosswalks.findByPatientIdAndSourceId(patientId, medicareSourceId());
    }

    /**
     * Starts linking (or re-linking) this patient's Medicare account and returns the one-time
     * link token the browser will carry. An existing link keeps working until the new sign-in
     * completes, so a patient who abandons a re-link is not left disconnected.
     */
    @Transactional
    public String startLink(final Long patientId) {
        Objects.requireNonNull(patientId, "patientId");
        final EhrPatientCrosswalk crosswalk = crosswalkFor(patientId).orElseGet(() -> EhrPatientCrosswalk.builder()
                .patientId(patientId)
                .sourceId(medicareSourceId())
                .build());
        final String linkToken = newLinkToken();
        crosswalk.setLinkToken(linkToken);
        crosswalk.setLinkTokenExpiresAt(clock.instant().plus(LINK_TOKEN_TTL));
        crosswalks.save(crosswalk);
        return linkToken;
    }

    /** A pending link for this token, if the token exists and has not expired. */
    public Optional<EhrPatientCrosswalk> pendingLink(final String linkToken) {
        if (linkToken == null || linkToken.isBlank()) {
            return Optional.empty();
        }
        return crosswalks.findByLinkToken(linkToken)
                .filter(c -> c.getLinkTokenExpiresAt() != null && clock.instant().isBefore(c.getLinkTokenExpiresAt()));
    }

    /**
     * Finishes a link once Blue Button has called back with tokens for {@code externalPatientId}.
     * The link token is cleared either way it ends, so it cannot be replayed.
     */
    @Transactional
    public LinkOutcome completeLink(
            final String linkToken,
            final String externalPatientId,
            final String accessToken,
            final Instant accessTokenExpiresAt,
            final String refreshToken) {
        final Optional<EhrPatientCrosswalk> pending = pendingLink(linkToken);
        if (pending.isEmpty() || externalPatientId == null || externalPatientId.isBlank()
                || accessToken == null || accessToken.isBlank()) {
            return LinkOutcome.LINK_EXPIRED;
        }
        final EhrPatientCrosswalk crosswalk = pending.get();

        // One Medicare record can belong to one CareConnect patient (uq_ehr_crosswalk_source_external).
        final Optional<EhrPatientCrosswalk> owner =
                crosswalks.findBySourceIdAndExternalPatientId(crosswalk.getSourceId(), externalPatientId);
        if (owner.isPresent() && !owner.get().getId().equals(crosswalk.getId())) {
            abandon(crosswalk);
            return LinkOutcome.ALREADY_LINKED_ELSEWHERE;
        }

        final LocalDateTime now = LocalDateTime.now(clock);
        crosswalk.setExternalPatientId(externalPatientId);
        crosswalk.setToken(cryptor.encrypt(accessToken));
        crosswalk.setTokenExpiresAt(accessTokenExpiresAt);
        crosswalk.setRefreshToken(refreshToken == null || refreshToken.isBlank() ? null : cryptor.encrypt(refreshToken));
        crosswalk.setLastLoggedIn(now);
        crosswalk.setLastRefreshed(now);
        crosswalk.setLinkToken(null);
        crosswalk.setLinkTokenExpiresAt(null);
        crosswalks.save(crosswalk);
        return LinkOutcome.CONNECTED;
    }

    /**
     * The patient cancelled or the sign-in failed (FR-MCR-05, FR-MCR-08): leave them as they were.
     * A row that was only ever pending is removed; an existing link is kept.
     */
    @Transactional
    public void abandonLink(final String linkToken) {
        if (linkToken == null || linkToken.isBlank()) {
            return;
        }
        crosswalks.findByLinkToken(linkToken).ifPresent(this::abandon);
    }

    private void abandon(final EhrPatientCrosswalk crosswalk) {
        if (crosswalk.isLinked()) {
            crosswalk.setLinkToken(null);
            crosswalk.setLinkTokenExpiresAt(null);
            crosswalks.save(crosswalk);
        } else {
            crosswalks.delete(crosswalk);
        }
    }

    /** Whether this patient has Medicare linked. A pending link that never finished is not linked. */
    public ConnectionStatus status(final Long patientId) {
        return crosswalkFor(patientId)
                .filter(EhrPatientCrosswalk::isLinked)
                .map(c -> new ConnectionStatus(true, "LINKED", c.getLastLoggedIn()))
                .orElseGet(ConnectionStatus::unlinked);
    }

    /**
     * Unlinks this patient's Medicare account (FR-MCR-10/11, Addendum A1-Q1). Returns once everything
     * below is gone, so the caller can confirm only after the deletes have committed.
     * <p>
     * <b>Deleted:</b> the tokens and the connection (the crosswalk row), and every Medicare row in
     * {@code ehr_raw_payload}, {@code ehr_source_identity}, {@code ehr_coverage_record},
     * {@code ehr_visit_record} and {@code ehr_identity_conflict}.
     * <p>
     * <b>Kept:</b> the CareConnect account and all non-Medicare data; demographics reconciliation
     * already applied to {@code patient}; {@code ehr_identity_field_provenance}, which holds no
     * patient values and keeps recency correct if the patient links again; and
     * {@code ehr_audit_event}, the access log, which stays under the 7-year / age-25 rule.
     * <p>
     * The grant is revoked at Blue Button first, while the token still exists. A failed revoke is
     * logged by {@link MedicareService#revoke} and does not stop the unlink: the patient asked for
     * their data to go, and the token is deleted here either way.
     *
     * @return true if there was anything to unlink
     */
    public boolean disconnect(final Long patientId) {
        final Optional<EhrPatientCrosswalk> crosswalk = crosswalkFor(patientId);
        if (crosswalk.isEmpty()) {
            return false;
        }
        accessToken(crosswalk.get()).ifPresent(medicare::revoke);
        // One transaction, outside the HTTP call above: all of it goes, or none of it does.
        transactions.executeWithoutResult(status -> deleteMedicareData(patientId, crosswalk.get()));
        return true;
    }

    private void deleteMedicareData(final Long patientId, final EhrPatientCrosswalk crosswalk) {
        final Long source = crosswalk.getSourceId();
        stores.rawPayloads().deleteAllForPatientAndSource(patientId, source);
        stores.sourceIdentities().deleteAllForPatientAndSource(patientId, source);
        stores.coverages().deleteAllForPatientAndSource(patientId, source);
        stores.visits().deleteAllForPatientAndSource(patientId, source);
        stores.conflicts().deleteAllForPatientAndSource(patientId, source);
        crosswalks.delete(crosswalk);
    }

    /**
     * A usable access token for a linked crosswalk row, for calls to Blue Button. A token at or near
     * its stated expiry is refreshed first with the stored refresh token (STP-M3-E-12). If Blue Button
     * rejects the refresh, the link is marked Unlinked (FR-MCR-09) and the result is empty. If the
     * refresh merely fails (network, server error), the current token is returned and the call can
     * still be tried.
     */
    public Optional<String> accessToken(final EhrPatientCrosswalk crosswalk) {
        if (crosswalk == null || !crosswalk.isLinked()) {
            return Optional.empty();
        }
        final Instant expiresAt = crosswalk.getTokenExpiresAt();
        final boolean due = expiresAt != null && !clock.instant().isBefore(expiresAt.minus(REFRESH_MARGIN));
        if (due && crosswalk.getRefreshToken() != null) {
            final MedicareTokenRefresher.Result result = refresher.refresh(cryptor.decrypt(crosswalk.getRefreshToken()));
            if (result instanceof MedicareTokenRefresher.Refreshed refreshed) {
                crosswalk.setToken(cryptor.encrypt(refreshed.accessToken()));
                crosswalk.setTokenExpiresAt(refreshed.expiresAt());
                if (refreshed.refreshToken() != null) {
                    crosswalk.setRefreshToken(cryptor.encrypt(refreshed.refreshToken()));
                }
                crosswalk.setLastRefreshed(LocalDateTime.now(clock));
                crosswalks.save(crosswalk);
                return Optional.of(refreshed.accessToken());
            }
            if (result instanceof MedicareTokenRefresher.Rejected) {
                markUnlinked(crosswalk);
                return Optional.empty();
            }
            log.warn("Medicare token refresh failed; trying the current token: {}",
                    ((MedicareTokenRefresher.Failed) result).reason());
        }
        return Optional.of(cryptor.decrypt(crosswalk.getToken()));
    }

    /** {@link #accessToken}, or ERR-MCR-05 when there is no working link. */
    public String requireAccessToken(final EhrPatientCrosswalk crosswalk) {
        return accessToken(crosswalk).orElseThrow(MedicareNotConnectedException::new);
    }

    /**
     * Blue Button rejected this patient's token (FR-MCR-09): set the link to Unlinked so no further
     * call is made with it (AC-MCR-09-2). Unlike {@link #disconnect}, the Medicare data stays: this
     * is the token lapsing, not the patient asking for their data to go. Linking again reuses the row.
     */
    public void markTokenRejected(final Long patientId) {
        crosswalkFor(patientId).filter(EhrPatientCrosswalk::isLinked).ifPresent(this::markUnlinked);
    }

    private void markUnlinked(final EhrPatientCrosswalk crosswalk) {
        crosswalk.setToken(null);
        crosswalk.setRefreshToken(null);
        crosswalk.setTokenExpiresAt(null);
        crosswalks.save(crosswalk);
    }

    private static String newLinkToken() {
        final byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
