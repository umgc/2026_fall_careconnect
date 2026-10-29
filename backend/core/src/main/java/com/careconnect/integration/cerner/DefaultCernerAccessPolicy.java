package com.careconnect.integration.cerner;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/** Applies CareConnect's existing patient relationship policy to Cerner reads. */
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class DefaultCernerAccessPolicy implements CernerAccessPolicy {

    private final UserRepository users;
    private final PatientRepository patients;
    private final AuthorizationService authorization;

    @Override
    public boolean canView(final String username, final long patientId) {
        User caller = users.findByEmail(username).orElse(null);
        Long patientUserId = patients.findById(patientId)
                .map(Patient::getUser)
                .map(User::getId)
                .orElse(null);
        if (caller == null || patientUserId == null) {
            return false;
        }
        try {
            authorization.requirePatientAccess(caller, patientUserId);
            return true;
        } catch (UnauthorizedException | IllegalArgumentException exception) {
            return false;
        }
    }
}
