package com.careconnect.service;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Objects;

/** Resolves the single authoritative patient participant for a call. */
@Service
@RequiredArgsConstructor
public class CallPatientResolver {

    private final CallTelemetryService callTelemetryService;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;

    public Long requirePatientId(final String callId) {
        final List<Long> patientIds = callTelemetryService.getTelemetryForCall(callId).stream()
                .filter(event -> "CALL_JOIN".equals(event.getEventType()))
                .map(event -> event.getActorUserId())
                .filter(Objects::nonNull)
                .distinct()
                .map(userRepository::findById)
                .flatMap(java.util.Optional::stream)
                .filter(user -> user.getRole() == Role.PATIENT)
                .map(User::getId)
                .map(patientRepository::findByUserId)
                .flatMap(java.util.Optional::stream)
                .map(Patient::getId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();

        if (patientIds.size() != 1) {
            throw new IllegalStateException(
                    "Call must resolve to exactly one patient before summary persistence");
        }
        return patientIds.get(0);
    }
}
