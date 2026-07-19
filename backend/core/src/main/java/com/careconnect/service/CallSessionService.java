package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import java.util.List;
import java.util.Objects;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Owns durable call authorization, patient mapping, and lifecycle state. */
@Service
@RequiredArgsConstructor
@Transactional
public class CallSessionService {

    public static final String SESSION_CREATED = "CREATED";
    public static final String SESSION_ACTIVE = "ACTIVE";
    public static final String SESSION_TERMINATING = "TERMINATING";
    public static final String SESSION_ENDED = "ENDED";
    public static final String SESSION_CANCELLED = "CANCELLED";
    public static final String PARTICIPANT_INVITED = "INVITED";
    public static final String PARTICIPANT_JOINED = "JOINED";
    public static final String PARTICIPANT_LEFT = "LEFT";
    public static final String PARTICIPANT_DECLINED = "DECLINED";
    public static final String PARTICIPANT_EXPIRED = "EXPIRED";

    private final CallSessionRepository callSessionRepository;
    private final CallParticipantRepository callParticipantRepository;
    private final PatientRepository patientRepository;
    private final UserRepository userRepository;
    private final CaregiverPatientLinkService caregiverPatientLinkService;
    private final FamilyMemberService familyMemberService;
    private final ScheduledVisitRepository scheduledVisitRepository;
    private final CaregiverRepository caregiverRepository;

    public record LeaveResult(boolean terminationOwner, boolean ended, long remainingParticipants) {}
    public record DeclineResult(List<Long> notifyUserIds, boolean terminationOwner) {}

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
        validateScheduledVisit(scheduledVisitId, patient.getId(), creator);

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
        if (!SESSION_CREATED.equals(session.getStatus())
                && !SESSION_ACTIVE.equals(session.getStatus())) {
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
        final boolean durableParticipant = callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), user.getId())
                .filter(p -> PARTICIPANT_JOINED.equals(p.getStatus())
                        || PARTICIPANT_LEFT.equals(p.getStatus())
                        || PARTICIPANT_EXPIRED.equals(p.getStatus()))
                .isPresent();
        if (durableParticipant) {
            return session;
        }
        throw new AppException(HttpStatus.FORBIDDEN, "User has no durable recording access");
    }

    public void recordJoin(
            final CallSession session, final Long userId, final String chimeMeetingId) {
        final CallSession locked = callSessionRepository.findByCallIdForLifecycle(session.getCallId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (callSessionRepository.activateIfJoinable(
                locked.getId(), chimeMeetingId, SESSION_CREATED, SESSION_ACTIVE) != 1
                || callParticipantRepository.markJoinedIfInvited(
                        locked.getId(), userId, PARTICIPANT_INVITED, PARTICIPANT_JOINED) != 1) {
            throw new AppException(HttpStatus.GONE, "Call is no longer joinable");
        }
    }

    public CallParticipant addAuthorizedParticipant(
            final String callId, final User inviter, final User invitee) {
        final CallSession session = requireJoinAuthorized(callId, inviter.getId());
        final Long patientUserId = requirePatientUserId(session);
        authorizeForPatient(invitee, patientUserId);
        return upsertParticipant(
                session, invitee.getId(), inviter.getId(), PARTICIPANT_INVITED);
    }

    public LeaveResult leaveOrBeginTermination(final String callId, final Long userId) {
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        final CallParticipant participant = callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .orElseThrow(() -> new AppException(
                        HttpStatus.FORBIDDEN, "User is not authorized for this call"));
        if (SESSION_ENDED.equals(session.getStatus()) || SESSION_CANCELLED.equals(session.getStatus())) {
            return new LeaveResult(false, true, 0);
        }
        if (SESSION_TERMINATING.equals(session.getStatus())) {
            return new LeaveResult(false, false, 0);
        }
        if (!PARTICIPANT_JOINED.equals(participant.getStatus())) {
            throw new AppException(HttpStatus.FORBIDDEN, "User must join the call before this operation");
        }
        callParticipantRepository.markLeftIfJoined(
                session.getId(), userId, PARTICIPANT_JOINED, PARTICIPANT_LEFT);
        final long remaining = callParticipantRepository.countByCallSessionIdAndStatus(
                session.getId(), PARTICIPANT_JOINED);
        if (remaining > 1) {
            return new LeaveResult(false, false, remaining);
        }
        final boolean owner = callSessionRepository.beginTermination(
                session.getId(), SESSION_CREATED, SESSION_ACTIVE, SESSION_TERMINATING) == 1;
        return new LeaveResult(owner, false, remaining);
    }

    public void completeTermination(final String callId) {
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        callParticipantRepository.expireJoinedParticipants(
                session.getId(), PARTICIPANT_JOINED, PARTICIPANT_EXPIRED);
        callSessionRepository.completeTermination(
                session.getId(), SESSION_TERMINATING, SESSION_ENDED);
    }

    public DeclineResult declineInvitation(final String callId, final Long userId) {
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (callParticipantRepository.declineIfInvited(
                session.getId(), userId, PARTICIPANT_INVITED, PARTICIPANT_DECLINED) != 1) {
            throw new AppException(HttpStatus.CONFLICT, "Invitation is no longer pending");
        }
        final List<Long> notify = callParticipantRepository.findByCallSessionId(session.getId()).stream()
                .filter(p -> !Objects.equals(p.getUserId(), userId))
                .filter(p -> PARTICIPANT_INVITED.equals(p.getStatus())
                        || PARTICIPANT_JOINED.equals(p.getStatus()))
                .map(CallParticipant::getUserId)
                .toList();
        if (SESSION_CREATED.equals(session.getStatus())) {
            callSessionRepository.cancelIfNotActive(
                    session.getId(), SESSION_CREATED, SESSION_CANCELLED);
            return new DeclineResult(notify, false);
        }
        final long joined = callParticipantRepository.countByCallSessionIdAndStatus(
                session.getId(), PARTICIPANT_JOINED);
        final boolean terminationOwner = joined <= 1 && callSessionRepository.beginTermination(
                session.getId(), SESSION_CREATED, SESSION_ACTIVE, SESSION_TERMINATING) == 1;
        return new DeclineResult(notify, terminationOwner);
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

    @Transactional(readOnly = true)
    public Long requirePendingInvitationRecipient(
            final String callId, final Long senderUserId, final Long requestedRecipientId) {
        final CallSession session = requireJoinAuthorized(callId, senderUserId);
        final List<Long> pending = callParticipantRepository.findByCallSessionId(session.getId()).stream()
                .filter(p -> PARTICIPANT_INVITED.equals(p.getStatus()))
                .map(CallParticipant::getUserId)
                .filter(id -> !Objects.equals(id, senderUserId))
                .toList();
        if (pending.size() != 1 || !Objects.equals(pending.get(0), requestedRecipientId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Recipient is not a pending call invitee");
        }
        return pending.get(0);
    }

    @Transactional(readOnly = true)
    public List<Long> getOtherParticipantUserIds(final String callId, final Long actorUserId) {
        final CallSession session = requireParticipant(callId, actorUserId);
        return callParticipantRepository.findByCallSessionId(session.getId()).stream()
                .filter(p -> !Objects.equals(p.getUserId(), actorUserId))
                .filter(p -> PARTICIPANT_INVITED.equals(p.getStatus())
                        || PARTICIPANT_JOINED.equals(p.getStatus())
                        || PARTICIPANT_LEFT.equals(p.getStatus()))
                .map(CallParticipant::getUserId)
                .toList();
    }

    private CallSession requireSameOwnership(
            final CallSession existing,
            final Long patientId,
            final Long creatorUserId,
            final Long scheduledVisitId) {
        if (!Objects.equals(existing.getPatientId(), patientId)
                || !Objects.equals(existing.getCreatedByUserId(), creatorUserId)
                || !Objects.equals(existing.getScheduledVisitId(), scheduledVisitId)
                || SESSION_TERMINATING.equals(existing.getStatus())
                || SESSION_ENDED.equals(existing.getStatus())
                || SESSION_CANCELLED.equals(existing.getStatus())) {
            throw new AppException(HttpStatus.CONFLICT, "callId is already in use");
        }
        return existing;
    }

    private CallParticipant upsertParticipant(
            final CallSession session,
            final Long userId,
            final Long invitedByUserId,
            final String initialStatus) {
        final var existing = callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId);
        if (existing.isPresent()) {
            return existing.get();
        }
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

    private void validateScheduledVisit(
            final Long scheduledVisitId, final Long patientId, final User creator) {
        if (scheduledVisitId == null) {
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
        if (creator.getRole() != com.careconnect.security.Role.CAREGIVER) {
            return;
        }
        final Long caregiverId = caregiverRepository.findByUserId(creator.getId())
                .map(com.careconnect.model.Caregiver::getId)
                .orElseThrow(() -> new AppException(HttpStatus.FORBIDDEN, "Caregiver profile not found"));
        if (!Objects.equals(caregiverId, visit.getCaregiverId())) {
            throw new AppException(HttpStatus.FORBIDDEN, "Scheduled visit is assigned to another caregiver");
        }
    }

    private void validateCallId(final String callId) {
        if (callId == null || callId.isBlank() || callId.length() > 120
                || !callId.matches("[A-Za-z0-9_-]+")) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Invalid callId");
        }
    }
}
