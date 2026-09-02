package com.careconnect.service;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.UnauthorizedException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * Resolves the patient record for USPS digest and email-credential endpoints from email,
 * numeric database id, or defaults to the authenticated user when no identifier is supplied.
 */
@Component
@RequiredArgsConstructor
public class UspsPatientResolver {

    private final UserRepository userRepository;

    private static String firstNonBlank(String first, String second) {
        if (first != null && !first.isBlank()) {
            return first.trim();
        }
        if (second != null && !second.isBlank()) {
            return second.trim();
        }
        return null;
    }

    private static Optional<Long> parseNumericUserId(String value) {
        try {
            return Optional.of(Long.parseLong(value));
        } catch (NumberFormatException e) {
            return Optional.empty();
        }
    }

    public User resolvePatient(String patientEmail, String userId, User currentUser) throws UnauthorizedException {
        String identifier = firstNonBlank(patientEmail, userId);
        if (identifier == null || identifier.isBlank()) {
            return currentUser;
        }
        if ("demo-user".equalsIgnoreCase(identifier)) {
            throw new UnauthorizedException("Invalid patient identifier: " + identifier);
        }
        User resolved = userRepository.findByEmail(identifier)
                .or(() -> parseNumericUserId(identifier).flatMap(userRepository::findById))
                .orElseThrow(() -> new UnauthorizedException(
                        "No patient found for identifier: " + identifier));
        if (!resolved.isPatient()) {
            throw new UnauthorizedException(
                    "Identifier does not refer to a patient: " + identifier);
        }
        return resolved;
    }

    public User resolvePatient(String patientIdentifier, User currentUser) throws UnauthorizedException {
        return resolvePatient(patientIdentifier, null, currentUser);
    }
}
