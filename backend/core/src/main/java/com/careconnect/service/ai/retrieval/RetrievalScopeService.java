package com.careconnect.service.ai.retrieval;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.EnumSet;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * Central RBAC scope resolver for Ask AI retrieval (WBS 3.2.3, FR-AI-1, REQ-SC-7/8).
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class RetrievalScopeService {

    private final AuthorizationService authorizationService;
    private final PatientRepository patientRepository;
    private final CaregiverPatientLinkService caregiverPatientLinkService;
    private final FamilyMemberService familyMemberService;
    private final RetrievalSourceExclusionProvider sourceExclusionProvider;
    private final RetrievalConsentProvider consentProvider;
    private final RetrievalScopeAuditService scopeAuditService;

    public RetrievalScope resolveRetrievalScope(User caller, Long patientId)
            throws ForbiddenScopeException, UnauthorizedException {
        return resolveRetrievalScope(caller, patientId, null);
    }

    public RetrievalScope resolveRetrievalScope(
            User caller,
            Long patientId,
            Set<RetrievalRecordType> requestedSourceTypes)
            throws ForbiddenScopeException, UnauthorizedException {
        authorizationService.requirePermission(caller, Permission.USE_AI_FEATURES);

        if (patientId == null) {
            throw new IllegalArgumentException("patientId is required");
        }

        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> denyPatientNotFound(caller, patientId));

        assertPatientAccess(caller, patient);

        User patientUser = patient.getUser();
        if (patientUser == null || patientUser.getId() == null) {
            throw denyPatientNotFound(caller, patientId);
        }

        Set<RetrievalRecordType> excludedRaw = sourceExclusionProvider.getExcludedSourceTypes(patientId);
        Set<RetrievalRecordType> excludedSourceTypes = excludedRaw == null || excludedRaw.isEmpty()
                ? Set.of()
                : EnumSet.copyOf(excludedRaw);

        Set<RetrievalRecordType> allowedSourceTypes = EnumSet.copyOf(
                RetrievalRecordType.defaultsForRole(caller.getRole()));
        allowedSourceTypes.removeAll(excludedSourceTypes);

        if (requestedSourceTypes != null && !requestedSourceTypes.isEmpty()) {
            allowedSourceTypes.retainAll(requestedSourceTypes);
        }

        if (allowedSourceTypes.isEmpty()) {
            throw denyNoPermittedSourceTypes(caller, patientId);
        }

        boolean consentGranted = resolveConsentGranted(caller, patientUser.getId());
        CaregiverVisibilityFilter visibilityFilter = new CaregiverVisibilityFilter(caller.getRole(), consentGranted);

        return new RetrievalScope(
                caller.getId(),
                caller.getRole(),
                Set.of(patientId),
                Set.copyOf(allowedSourceTypes),
                Set.copyOf(excludedSourceTypes),
                visibilityFilter,
                consentGranted
        );
    }

    public void assertCanAsk(User caller, Long patientId, Set<RetrievalRecordType> requestedSourceTypes)
            throws ForbiddenScopeException, UnauthorizedException {
        resolveRetrievalScope(caller, patientId, requestedSourceTypes);
    }

    private void assertPatientAccess(User caller, Patient patient) throws ForbiddenScopeException {
        Long patientEntityId = patient.getId();
        User patientUser = patient.getUser();
        if (patientUser == null || patientUser.getId() == null) {
            throw denyPatientNotFound(caller, patientEntityId);
        }

        Long patientUserId = patientUser.getId();
        Role role = caller.getRole();

        switch (role) {
            case ADMIN -> {
                return;
            }
            case PATIENT -> {
                if (!Objects.equals(caller.getId(), patientUserId)) {
                    throw denyPatientOutOfScope(caller, patientEntityId);
                }
            }
            case CAREGIVER -> {
                if (!caregiverPatientLinkService.hasAccessToPatient(caller.getId(), patientUserId)) {
                    throw denyPatientOutOfScope(caller, patientEntityId);
                }
            }
            case FAMILY_MEMBER -> {
                if (!familyMemberService.hasAccessToPatient(caller.getId(), patientUserId)) {
                    throw denyPatientOutOfScope(caller, patientEntityId);
                }
            }
            default -> throw denyUnsupportedRole(caller, role);
        }
    }

    private ForbiddenScopeException denyPatientNotFound(User caller, Long patientId) {
        String detail = String.format("Patient %d not found", patientId);
        UUID auditId = scopeAuditService.logScopeDenied(
                caller, patientId, ScopeDenialReason.PATIENT_NOT_FOUND, detail);
        return ForbiddenScopeException.of(
                ScopeDenialReason.PATIENT_NOT_FOUND, patientId, caller.getId(), detail, auditId);
    }

    private ForbiddenScopeException denyPatientOutOfScope(User caller, Long patientId) {
        String detail = String.format(
                "Patient %d is out of scope for user '%s'", patientId, caller.getEmail());
        UUID auditId = scopeAuditService.logScopeDenied(
                caller, patientId, ScopeDenialReason.PATIENT_OUT_OF_SCOPE, detail);
        return ForbiddenScopeException.of(
                ScopeDenialReason.PATIENT_OUT_OF_SCOPE, patientId, caller.getId(), detail, auditId);
    }

    private ForbiddenScopeException denyNoPermittedSourceTypes(User caller, Long patientId) {
        String detail = String.format(
                "No permitted source types remain for patient %d after RBAC and consent filters",
                patientId);
        UUID auditId = scopeAuditService.logScopeDenied(
                caller, patientId, ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES, detail);
        return ForbiddenScopeException.of(
                ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES, patientId, caller.getId(), detail, auditId);
    }

    private ForbiddenScopeException denyUnsupportedRole(User caller, Role role) {
        String detail = String.format("Role '%s' cannot resolve Ask AI retrieval scope", role);
        UUID auditId = scopeAuditService.logScopeDenied(
                caller, null, ScopeDenialReason.UNSUPPORTED_ROLE, detail);
        return ForbiddenScopeException.unsupportedRole(role, caller.getId(), detail, auditId);
    }

    private boolean resolveConsentGranted(User caller, Long patientUserId) {
        return switch (caller.getRole()) {
            case PATIENT, ADMIN -> true;
            case CAREGIVER -> consentProvider.isCaregiverConsentGranted(caller.getId(), patientUserId);
            case FAMILY_MEMBER -> false;
        };
    }
}
