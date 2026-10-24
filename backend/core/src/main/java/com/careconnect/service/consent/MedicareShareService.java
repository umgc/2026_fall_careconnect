package com.careconnect.service.consent;

import com.careconnect.dto.MedicareSharedWithMeResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.EmailService;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * CR-2 (#305) record sharing: a patient shares their Medicare records with another registered
 * CareConnect user, found by email, read-only for 90 days.
 *
 * <p>Built on {@code consent_grants} as #305 asks, with no new table: a share is a
 * {@link ConsentGrant#SCOPE_MEDICARE_VIEW} grant whose grantee role is
 * {@link ConsentGrant#GRANTEE_ROLE_SHARE_RECIPIENT} and whose expiry is fixed at 90 days. The
 * patient revokes it by share id ({@link #revokeShare}).
 *
 * <p>The grant row is the record of each share: who shared, with whom, when it started, when it
 * ends and when it was revoked. Share and revoke are also logged, by user and grant id only.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MedicareShareService {

    /** CR-2 scope: one fixed share length, not configurable. */
    static final Duration SHARE_DURATION = Duration.ofDays(90);

    private final ConsentGrantRepository consentGrantRepository;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final EmailService emailService;

    /**
     * Result of a share: the saved grant, the recipient, and whether the notice email went out.
     *
     * @param grant     the {@code MEDICARE_VIEW} grant
     * @param recipient the user the records are shared with; null if that user no longer exists
     * @param emailSent whether the notice email was sent
     */
    public record ShareResult(ConsentGrant grant, User recipient, boolean emailSent) {
    }

    /**
     * Shares the patient's Medicare records with the registered user who owns
     * {@code recipientEmail}, then emails that user a notice with no health data in it.
     *
     * <p>A failed email does not undo the share: the grant is the record of consent, and the
     * result reports {@code emailSent=false} so the app can tell the patient.
     *
     * @param patient        the authenticated patient sharing their records
     * @param recipientEmail email of a registered CareConnect user
     * @return the saved grant, the recipient, and whether the notice was sent
     * @throws AppException 400 when the email is blank or is the patient's own, 404 when no
     *                      registered user has that email, 409 when that user already has access
     */
    @Transactional
    public ShareResult shareMedicareRecords(final User patient, final String recipientEmail) {
        if (patient == null || patient.getId() == null) {
            throw new IllegalArgumentException("patient is required");
        }
        if (recipientEmail == null || recipientEmail.isBlank()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "recipientEmail is required");
        }
        final User recipient = findRegisteredUser(recipientEmail.trim())
                .orElseThrow(() -> new AppException(
                        HttpStatus.NOT_FOUND, "No registered CareConnect user has that email"));
        if (patient.getId().equals(recipient.getId())) {
            throw new AppException(
                    HttpStatus.BAD_REQUEST, "You cannot share your records with yourself");
        }

        final Long patientUserId = patient.getId();
        final Long recipientUserId = recipient.getId();
        final Instant now = Instant.now();
        // Soft-expired ACTIVE rows still occupy the unique ACTIVE index — revoke them first.
        final List<ConsentGrant> expired = new ArrayList<>();
        for (final ConsentGrant row : consentGrantRepository.findStatusActiveGrants(
                patientUserId, recipientUserId, ConsentGrant.SCOPE_MEDICARE_VIEW)) {
            if (row.getExpiresAt() != null && !row.getExpiresAt().isAfter(now)) {
                row.setStatus(ConsentGrant.STATUS_REVOKED);
                row.setRevokedAt(now);
                expired.add(row);
            }
        }
        if (!expired.isEmpty()) {
            consentGrantRepository.saveAll(expired);
        }
        // Never overwrite a live grant: a linked caregiver's open-ended MEDICARE_VIEW grant would
        // silently become a 90-day share, and a repeat share would quietly extend the 90 days.
        if (!consentGrantRepository.findActiveGrants(
                patientUserId, recipientUserId, ConsentGrant.SCOPE_MEDICARE_VIEW, now).isEmpty()) {
            throw new AppException(
                    HttpStatus.CONFLICT, "This person already has access to your Medicare records");
        }

        final ConsentGrant saved = consentGrantRepository.save(ConsentGrant.builder()
                .patientUserId(patientUserId)
                .granteeUserId(recipientUserId)
                .granteeRole(ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT)
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(now)
                .expiresAt(now.plus(SHARE_DURATION))
                .build());
        if (log.isInfoEnabled()) {
            log.info("Shared Medicare records: patient={} recipient={} grantId={} expiresAt={}",
                    patientUserId, recipientUserId, saved.getId(), saved.getExpiresAt());
        }

        boolean emailSent = true;
        try {
            emailService.sendMedicareShareNoticeEmail(
                    recipient.getEmail(), recipient.getName(), patient.getName(),
                    saved.getExpiresAt());
        } catch (RuntimeException e) {
            emailSent = false;
            log.warn("Medicare share notice email failed: grantId={} ({})",
                    saved.getId(), e.getClass().getSimpleName());
        }
        return new ShareResult(saved, recipient, emailSent);
    }

    /**
     * Lists the patient's current CR-2 shares (active, unexpired, held by a share recipient),
     * newest first. Caregiver {@code MEDICARE_VIEW} grants are not shares and are left out.
     *
     * @param patientUserId the patient's user id
     * @return the active shares; empty when there are none
     */
    @Transactional(readOnly = true)
    public List<ShareResult> listActiveShares(final Long patientUserId) {
        if (patientUserId == null) {
            return List.of();
        }
        final List<ShareResult> shares = new ArrayList<>();
        for (final ConsentGrant grant : consentGrantRepository.findActiveGrantsForPatient(
                patientUserId, ConsentGrant.SCOPE_MEDICARE_VIEW, Instant.now())) {
            if (ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT.equals(grant.getGranteeRole())) {
                shares.add(new ShareResult(
                        grant, userRepository.findById(grant.getGranteeUserId()).orElse(null),
                        false));
            }
        }
        return shares;
    }

    /**
     * The caller's "Shared with me" list: active, unexpired CR-2 shares they received, newest
     * first, each with the sharing patient's record id for the Medicare reads. Caregiver
     * {@code MEDICARE_VIEW} grants are not shares and are left out.
     *
     * @param recipientUserId the authenticated user's id
     * @return the shares received; empty when there are none
     */
    @Transactional(readOnly = true)
    public List<MedicareSharedWithMeResponse> listSharedWithMe(final Long recipientUserId) {
        if (recipientUserId == null) {
            return List.of();
        }
        final List<MedicareSharedWithMeResponse> received = new ArrayList<>();
        for (final ConsentGrant grant : consentGrantRepository.findActiveGrantsForGrantee(
                recipientUserId, ConsentGrant.SCOPE_MEDICARE_VIEW, Instant.now())) {
            if (!ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT.equals(grant.getGranteeRole())) {
                continue;
            }
            final Optional<Patient> record = patientRepository.findByUserId(grant.getPatientUserId());
            final String name = record.map(Patient::getUser).map(User::getName)
                    .or(() -> userRepository.findById(grant.getPatientUserId()).map(User::getName))
                    .orElse(null);
            received.add(new MedicareSharedWithMeResponse(
                    grant.getId(),
                    grant.getPatientUserId(),
                    record.map(Patient::getId).orElse(null),
                    name,
                    grant.getGrantedAt(),
                    grant.getExpiresAt()));
        }
        return received;
    }

    /**
     * Revokes one of the patient's shares by its grant id. Only a CR-2 share the patient issued
     * can be revoked here, so this can never end a caregiver's {@code MEDICARE_VIEW} grant.
     * Revoking a share that already ended is a no-op that returns it unchanged.
     *
     * @param patientUserId the authenticated patient's user id
     * @param shareId       the share's grant id
     * @return the share as it now stands
     * @throws AppException 404 when no share with that id belongs to the patient (another
     *                      patient's share and a caregiver grant look the same as a missing one)
     */
    @Transactional
    public ShareResult revokeShare(final Long patientUserId, final Long shareId) {
        final ConsentGrant grant = (shareId == null ? Optional.<ConsentGrant>empty()
                : consentGrantRepository.findById(shareId))
                .filter(g -> g.getPatientUserId() != null && g.getPatientUserId().equals(patientUserId))
                .filter(g -> ConsentGrant.SCOPE_MEDICARE_VIEW.equals(g.getScope()))
                .filter(g -> ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT.equals(g.getGranteeRole()))
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Share not found"));
        final User recipient = userRepository.findById(grant.getGranteeUserId()).orElse(null);
        if (!ConsentGrant.STATUS_ACTIVE.equals(grant.getStatus())) {
            return new ShareResult(grant, recipient, false);
        }
        grant.setStatus(ConsentGrant.STATUS_REVOKED);
        grant.setRevokedAt(Instant.now());
        final ConsentGrant saved = consentGrantRepository.save(grant);
        if (log.isInfoEnabled()) {
            log.info("Revoked Medicare share: patient={} recipient={} grantId={}",
                    patientUserId, saved.getGranteeUserId(), saved.getId());
        }
        return new ShareResult(saved, recipient, false);
    }

    private Optional<User> findRegisteredUser(final String email) {
        final Optional<User> exact = userRepository.findByEmail(email);
        if (exact.isPresent()) {
            return exact;
        }
        final String lower = email.toLowerCase(Locale.ROOT);
        return lower.equals(email) ? Optional.empty() : userRepository.findByEmail(lower);
    }
}
