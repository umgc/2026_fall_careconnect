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
                .orElseThrow(() -> ForbiddenScopeException.patientNotFound(patientId));

        assertPatientAccess(caller, patient);

        User patientUser = patient.getUser();
        if (patientUser == null || patientUser.getId() == null) {
            throw ForbiddenScopeException.patientNotFound(patientId);
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
            throw ForbiddenScopeException.noPermittedSourceTypes(patientId);
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
            throw ForbiddenScopeException.patientNotFound(patientEntityId);
        }

        Long patientUserId = patientUser.getId();
        Role role = caller.getRole();

        switch (role) {
            case ADMIN -> {
                return;
            }
            case PATIENT -> {
                if (!Objects.equals(caller.getId(), patientUserId)) {
                    throw ForbiddenScopeException.patientOutOfScope(patientEntityId, caller.getEmail());
                }
            }
            case CAREGIVER -> {
                if (!caregiverPatientLinkService.hasAccessToPatient(caller.getId(), patientUserId)) {
                    throw ForbiddenScopeException.patientOutOfScope(patientEntityId, caller.getEmail());
                }
            }
            case FAMILY_MEMBER -> {
                if (!familyMemberService.hasAccessToPatient(caller.getId(), patientUserId)) {
                    throw ForbiddenScopeException.patientOutOfScope(patientEntityId, caller.getEmail());
                }
            }
            default -> throw ForbiddenScopeException.unsupportedRole(role);
        }
    }

    private boolean resolveConsentGranted(User caller, Long patientUserId) {
        return switch (caller.getRole()) {
            case PATIENT, ADMIN -> true;
            case CAREGIVER -> consentProvider.isCaregiverConsentGranted(caller.getId(), patientUserId);
            case FAMILY_MEMBER -> false;
        };
    }
}
