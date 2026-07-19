package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Objects;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Owns durable call authorization, patient mapping, and lifecycle state. */
@Service
@RequiredArgsConstructor
@Transactional
public class CallSessionService {

    public static final String SESSION_CREATED = "CREATED";
    public static final String SESSION_ACTIVE = "ACTIVE";
    public static final String SESSION_ENDED = "ENDED";
    public static final String PARTICIPANT_INVITED = "INVITED";
    public static final String PARTICIPANT_JOINED = "JOINED";
    public static final String PARTICIPANT_LEFT = "LEFT";

    private final CallSessionRepository callSessionRepository;
    private final CallParticipantRepository callParticipantRepository;
    private final PatientRepository patientRepository;
    private final UserRepository userRepository;
    private final CaregiverPatientLinkService caregiverPatientLinkService;
    private final FamilyMemberService familyMemberService;
    @Autowired(required = false)
    private ScheduledVisitRepository scheduledVisitRepository;

    public CallSession createSession(
            final String callId,
            final Long patientUserId,
            final Long inviteeUserId,
            final Long scheduledVisitId,
            final User creator) {
        validateCallId(callId);
        if (creator == null || creator.getId() == null) {
            throw new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated");
        }
        if (patientUserId == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "patientUserId is required");
        }

        final Patient patient = patientRepository.findByUserId(patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));
        authorizeForPatient(creator, patientUserId);
        validateScheduledVisit(scheduledVisitId, patient.getId());

        final String normalizedCallId = callId.trim();
        callSessionRepository.insertIfAbsent(
                normalizedCallId,
                patient.getId(),
                creator.getId(),
                scheduledVisitId,
                SESSION_CREATED);
        final CallSession session = callSessionRepository.findByCallId(normalizedCallId)
                .map(existing -> requireSameOwnership(
                        existing, patient.getId(), creator.getId(), scheduledVisitId))
                // Keeps isolated unit tests and non-PostgreSQL developer stores usable.
                // Production PostgreSQL takes the atomic INSERT ... ON CONFLICT path above.
                .orElseGet(() -> {
                    final CallSession created = new CallSession();
                    created.setCallId(normalizedCallId);
                    created.setPatientId(patient.getId());
                    created.setCreatedByUserId(creator.getId());
                    created.setScheduledVisitId(scheduledVisitId);
                    created.setStatus(SESSION_CREATED);
                    return callSessionRepository.save(created);
                });

        upsertParticipant(session, creator.getId(), creator.getId(), PARTICIPANT_INVITED);
        if (inviteeUserId != null) {
            final User invitee = userRepository.findById(inviteeUserId)
                    .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Invitee not found"));
            authorizeForPatient(invitee, patientUserId);
            upsertParticipant(session, invitee.getId(), creator.getId(), PARTICIPANT_INVITED);
        }
        return session;
    }

    @Transactional(readOnly = true)
    public CallSession requireSession(final String callId) {
        return callSessionRepository.findByCallId(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
    }

    @Transactional(readOnly = true)
    public CallSession requireJoinAuthorized(final String callId, final Long userId) {
        final CallSession session = requireSession(callId);
        if (SESSION_ENDED.equals(session.getStatus())) {
            throw new AppException(HttpStatus.GONE, "Call is no longer active");
        }
        if (userId == null || callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .isEmpty()) {
            throw new AppException(HttpStatus.FORBIDDEN, "User is not authorized for this call");
        }
        return session;
    }

    /** Requires durable authorization, including historical participants who have left. */
    @Transactional(readOnly = true)
    public CallSession requireParticipant(final String callId, final Long userId) {
        final CallSession session = requireSession(callId);
        if (userId == null || callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .isEmpty()) {
            throw new AppException(HttpStatus.FORBIDDEN, "User is not authorized for this call");
        }
        return session;
    }

    /** Requires a participant who actually joined and has not left. */
    @Transactional(readOnly = true)
    public CallSession requireActiveParticipant(final String callId, final Long userId) {
        final CallSession session = requireJoinAuthorized(callId, userId);
        final CallParticipant participant = callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .orElseThrow(() -> new AppException(
                        HttpStatus.FORBIDDEN, "User is not authorized for this call"));
        if (!PARTICIPANT_JOINED.equals(participant.getStatus())) {
            throw new AppException(
                    HttpStatus.FORBIDDEN, "User must join the call before this operation");
        }
        return session;
    }

    /**
     * Recording metadata/playback requires active participation or a durable
     * patient relationship. Administrator access is an explicit policy branch.
     */
    @Transactional(readOnly = true)
    public CallSession requireRecordingAccess(final String callId, final User user) {
        final CallSession session = requireSession(callId);
        if (user == null || user.getId() == null) {
            throw new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated");
        }
        if (user.getRole() == com.careconnect.security.Role.ADMIN) {
            return session;
        }
        final boolean activeParticipant = callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), user.getId())
                .filter(p -> PARTICIPANT_JOINED.equals(p.getStatus()))
                .isPresent();
        if (activeParticipant) {
            return session;
        }
        authorizeForPatient(user, requirePatientUserId(session));
        return session;
    }

    public void recordJoin(
            final CallSession session, final Long userId, final String chimeMeetingId) {
        final CallParticipant participant = callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .orElseThrow(() -> new AppException(
                        HttpStatus.FORBIDDEN, "User is not authorized for this call"));
        participant.setStatus(PARTICIPANT_JOINED);
        participant.setJoinedAt(LocalDateTime.now());
        participant.setLeftAt(null);
        callParticipantRepository.save(participant);

        if (chimeMeetingId != null && !chimeMeetingId.isBlank()) {
            session.setChimeMeetingId(chimeMeetingId);
        }
        session.setStatus(SESSION_ACTIVE);
        callSessionRepository.save(session);
    }

    public CallParticipant addAuthorizedParticipant(
            final String callId, final User inviter, final User invitee) {
        final CallSession session = requireJoinAuthorized(callId, inviter.getId());
        final Long patientUserId = requirePatientUserId(session);
        authorizeForPatient(invitee, patientUserId);
        return upsertParticipant(
                session, invitee.getId(), inviter.getId(), PARTICIPANT_INVITED);
    }

    public void recordLeave(final String callId, final Long userId, final boolean ended) {
        final CallSession session = requireJoinAuthorized(callId, userId);
        callParticipantRepository.findByCallSessionIdAndUserId(session.getId(), userId)
                .ifPresent(participant -> {
                    participant.setStatus(PARTICIPANT_LEFT);
                    participant.setLeftAt(LocalDateTime.now());
                    callParticipantRepository.save(participant);
                });
        if (ended) {
            session.setStatus(SESSION_ENDED);
            session.setEndedAt(LocalDateTime.now());
            callSessionRepository.save(session);
        }
    }

    @Transactional(readOnly = true)
    public Long requirePatientUserId(final CallSession session) {
        final Patient patient = patientRepository.findById(session.getPatientId())
                .orElseThrow(() -> new IllegalStateException("Call session patient does not exist"));
        if (patient.getUser() == null || patient.getUser().getId() == null) {
            throw new IllegalStateException("Call session patient has no user mapping");
        }
        return patient.getUser().getId();
    }

    @Transactional(readOnly = true)
    public List<CallParticipant> getParticipants(final String callId) {
        final CallSession session = requireSession(callId);
        return callParticipantRepository.findByCallSessionId(session.getId());
    }

    @Transactional(readOnly = true)
    public List<CallParticipant> getJoinedParticipants(final String callId) {
        final CallSession session = requireSession(callId);
        return callParticipantRepository.findByCallSessionIdAndStatus(
                session.getId(), PARTICIPANT_JOINED);
    }

    private CallSession requireSameOwnership(
            final CallSession existing,
            final Long patientId,
            final Long creatorUserId,
            final Long scheduledVisitId) {
        if (!Objects.equals(existing.getPatientId(), patientId)
                || !Objects.equals(existing.getCreatedByUserId(), creatorUserId)
                || !Objects.equals(existing.getScheduledVisitId(), scheduledVisitId)
                || SESSION_ENDED.equals(existing.getStatus())) {
            throw new AppException(HttpStatus.CONFLICT, "callId is already in use");
        }
        return existing;
    }

    private CallParticipant upsertParticipant(
            final CallSession session,
            final Long userId,
            final Long invitedByUserId,
            final String initialStatus) {
        callParticipantRepository.insertIfAbsent(
                session.getId(), userId, invitedByUserId, initialStatus);
        return callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .orElseGet(() -> {
                    final CallParticipant participant = new CallParticipant();
                    participant.setCallSessionId(session.getId());
                    participant.setUserId(userId);
                    participant.setInvitedByUserId(invitedByUserId);
                    participant.setStatus(initialStatus);
                    return callParticipantRepository.save(participant);
                });
    }

    private void authorizeForPatient(final User user, final Long patientUserId) {
        final boolean authorized = switch (user.getRole()) {
            case ADMIN -> true;
            case PATIENT -> Objects.equals(user.getId(), patientUserId);
            case CAREGIVER -> caregiverPatientLinkService.hasAccessToPatient(
                    user.getId(), patientUserId);
            case FAMILY_MEMBER -> familyMemberService.hasAccessToPatient(
                    user.getId(), patientUserId);
        };
        if (!authorized) {
            throw new AppException(
                    HttpStatus.FORBIDDEN, "User is not authorized for this patient");
        }
    }

    private void validateScheduledVisit(final Long scheduledVisitId, final Long patientId) {
        if (scheduledVisitId == null || scheduledVisitRepository == null) {
            return;
        }
        final com.careconnect.model.schedule.ScheduledVisit visit =
                scheduledVisitRepository.findById(scheduledVisitId)
                        .orElseThrow(() -> new AppException(
                                HttpStatus.NOT_FOUND, "Scheduled visit not found"));
        if (!Objects.equals(visit.getPatientId(), patientId)) {
            throw new AppException(
                    HttpStatus.FORBIDDEN, "Scheduled visit does not belong to this patient");
        }
    }

    private void validateCallId(final String callId) {
        if (callId == null || callId.isBlank() || callId.length() > 120
                || !callId.matches("[A-Za-z0-9_-]+")) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Invalid callId");
        }
    }
}
