package com.careconnect.service;

import com.careconnect.repository.CallSessionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/** Resolves the single authoritative patient participant for a call. */
@Service
@RequiredArgsConstructor
public class CallPatientResolver {

    private final CallSessionRepository callSessionRepository;

    public Long requirePatientId(final String callId) {
        return callSessionRepository.findByCallId(callId)
                .map(session -> session.getPatientId())
                .filter(patientId -> patientId != null)
                .orElseThrow(() -> new IllegalStateException(
                        "Call must have an authoritative patient before summary persistence"));
    }
}
