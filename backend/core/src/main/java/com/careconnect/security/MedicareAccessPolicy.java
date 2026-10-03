package com.careconnect.security;

import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ConsentGrantRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * Who may read a patient's Medicare data: the patient themselves, or a caregiver assigned to them
 * whom the patient has given {@code MEDICARE_VIEW} consent. Nobody else.
 *
 * <p>This is how WBS 6.2.37's "tenant isolation … demonstrated through negative tests" is met.
 * CareConnect has no tenancy model and the {@code ehr_*} tables carry no organization column (the
 * 2026-09-26 org-scoping decision), so isolation is enforced per patient instead, as SRS FR-MCR-16
 * and FR-MCR-17 describe. Decided 2026-10-03.
 *
 * <p><b>Stricter than {@link AuthorizationService#requirePatientAccess}.</b> That check also admits
 * administrators and linked family members. Medicare data does not: FR-MCR-16 names only the owning
 * patient and an assigned caregiver, and the TDD records family-member and administrator access to
 * Medicare data as an open product decision, not a granted one. Widening this later is one
 * deliberate change here; narrowing a check that every Medicare endpoint already relies on is not.
 *
 * <p><b>A caregiver needs consent as well as the link</b> (SRS BR-02): an active, unexpired
 * caregiver-patient link, the {@code VIEW_ASSIGNED_PATIENTS} permission, <em>and</em> an active,
 * unexpired, unrevoked {@code consent_grants} row with scope {@code MEDICARE_VIEW} from that patient to
 * that caregiver. Being assigned to a patient is not the patient agreeing to share their Medicare
 * record. A grant for another scope, such as Ask AI's {@code AI_RETRIEVAL}, does not count.
 *
 * <p><b>Every refusal is a 404 with the same message</b> (FR-MCR-17, NFR-DEG-03). A 403 would
 * confirm that the patient exists and has Medicare data, which is itself disclosure; a refusal
 * that reads the same whatever the reason gives a caller nothing to probe with. The refusal is an
 * {@link AppException} carrying 404, because {@code GlobalExceptionHandler} maps that to its status;
 * a plain {@code NotFoundException} would reach its catch-all handler and leave as a 500.
 */
@Component
public class MedicareAccessPolicy {

    /** The one message every refusal carries, so refusals cannot be told apart. */
    static final String NOT_FOUND_MESSAGE = "Medicare data not found";

    /**
     * The {@code consent_grants.scope} a patient grants to let a caregiver see their Medicare data
     * (SRS BR-02). Kept here rather than on {@code ConsentGrant}, whose constants belong to Ask AI;
     * the column is free text, so a new scope needs no schema change.
     */
    public static final String SCOPE_MEDICARE_VIEW = "MEDICARE_VIEW";

    private final CaregiverPatientLinkRepository caregiverPatientLinks;
    private final ConsentGrantRepository consentGrants;

    public MedicareAccessPolicy(
            final CaregiverPatientLinkRepository caregiverPatientLinks,
            final ConsentGrantRepository consentGrants) {
        this.caregiverPatientLinks = Objects.requireNonNull(caregiverPatientLinks, "caregiverPatientLinks");
        this.consentGrants = Objects.requireNonNull(consentGrants, "consentGrants");
    }

    /**
     * Returns normally if {@code caller} may read {@code patientUserId}'s Medicare data, and throws
     * otherwise.
     *
     * @param caller        the signed-in user, from the JWT; never a value the client supplied
     * @param patientUserId the user id of the patient whose data is requested
     * @throws AppException with status 404 for every refusal, with the same message
     */
    public void requireMedicareAccess(final User caller, final Long patientUserId) {
        if (!mayAccess(caller, patientUserId)) {
            throw new AppException(HttpStatus.NOT_FOUND, NOT_FOUND_MESSAGE);
        }
    }

    private boolean mayAccess(final User caller, final Long patientUserId) {
        if (caller == null || caller.getId() == null || patientUserId == null) {
            return false;
        }
        if (caller.isPatient()) {
            return caller.getId().equals(patientUserId);
        }
        if (caller.isCaregiver()) {
            // Cheapest first, and each query only runs if the check before it passed.
            return caller.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)
                    && caregiverPatientLinks.existsActiveNonExpiredLinkByUserIds(
                            caller.getId(), patientUserId, LocalDateTime.now())
                    && consentGrants.existsActiveGrant(
                            patientUserId, caller.getId(), SCOPE_MEDICARE_VIEW, Instant.now());
        }
        // Administrators, family members and any other role: not granted for Medicare data.
        return false;
    }
}
