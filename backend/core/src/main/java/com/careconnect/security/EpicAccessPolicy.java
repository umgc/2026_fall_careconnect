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
 * Who may read a patient's EHR data (the generic {@code /api/ehr} read surface and the Epic
 * resource mirror): the patient themselves, or a caregiver assigned to them whom the patient has
 * given {@code EHR_VIEW} consent. Nobody else.
 *
 * <p>This is the Epic/EHR parallel of {@link MedicareAccessPolicy}: the same guarantee Team E's
 * Medicare connector provides via {@code MEDICARE_VIEW}, applied to the source-agnostic EHR read
 * surface. CareConnect has no tenancy model and the {@code ehr_*} tables carry no organization
 * column, so isolation is enforced per patient instead. See the Epic caregiver-consent access
 * model plan (2026-10-04).
 *
 * <p><b>Stricter than {@code AuthorizationService#requirePatientAccess}.</b> That check also admits
 * administrators and linked family members. EHR data does not: only the owning patient and an
 * assigned caregiver with consent. Widening this later is a deliberate change; it is not the
 * default.
 *
 * <p><b>A caregiver needs consent as well as the link:</b> an active, unexpired caregiver-patient
 * link, the {@code VIEW_ASSIGNED_PATIENTS} permission, <em>and</em> an active, unexpired, unrevoked
 * {@code consent_grants} row with scope {@code EHR_VIEW} from that patient to that caregiver. Being
 * assigned to a patient is not the patient agreeing to share their EHR record. A grant for another
 * scope, such as Ask AI's {@code AI_RETRIEVAL} or the patient's own {@code EHR_IMPORT} self-grant,
 * does not count.
 *
 * <p><b>Every refusal is a 404 with the same message.</b> A 403 would confirm that the patient
 * exists and has EHR data, which is itself disclosure; a refusal that reads the same whatever the
 * reason gives a caller nothing to probe with. The refusal is an {@link AppException} carrying 404,
 * because {@code GlobalExceptionHandler} maps that to its status.
 */
@Component
public class EpicAccessPolicy {

    /** The one message every refusal carries, so refusals cannot be told apart. */
    static final String NOT_FOUND_MESSAGE = "EHR data not found";

    /**
     * The {@code consent_grants.scope} a patient grants to let a caregiver see their EHR data.
     * Source-agnostic: one scope for the generic {@code /api/ehr} read surface, reusable for
     * Athena / Oracle later. Kept here rather than on {@code ConsentGrant}, whose constants belong
     * to Ask AI; the column is free text, so a new scope needs no schema change.
     */
    public static final String SCOPE_EHR_VIEW = "EHR_VIEW";

    private final CaregiverPatientLinkRepository caregiverPatientLinks;
    private final ConsentGrantRepository consentGrants;

    public EpicAccessPolicy(
            final CaregiverPatientLinkRepository caregiverPatientLinks,
            final ConsentGrantRepository consentGrants) {
        this.caregiverPatientLinks = Objects.requireNonNull(caregiverPatientLinks, "caregiverPatientLinks");
        this.consentGrants = Objects.requireNonNull(consentGrants, "consentGrants");
    }

    /**
     * Returns normally if {@code caller} may read {@code patientUserId}'s EHR data, and throws
     * otherwise.
     *
     * @param caller        the signed-in user, from the JWT; never a value the client supplied
     * @param patientUserId the user id of the patient whose data is requested
     * @throws AppException with status 404 for every refusal, with the same message
     */
    public void requireEhrReadAccess(final User caller, final Long patientUserId) {
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
                            patientUserId, caller.getId(), SCOPE_EHR_VIEW, Instant.now());
        }
        // Administrators, family members and any other role: not granted for EHR data.
        return false;
    }
}
