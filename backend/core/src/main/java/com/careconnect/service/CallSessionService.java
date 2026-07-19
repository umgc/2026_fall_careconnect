package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.Patient;
import com.careconnect.model.TerminationStep;
import com.careconnect.model.User;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.beans.factory.annotation.Value;

/** Owns durable call authorization, patient mapping, and lifecycle state. */
@Service
@RequiredArgsConstructor
@Transactional
public class CallSessionService {

    private static final long TERMINATION_LEASE_SECONDS = 120L;
    private static final long TERMINATION_RETRY_SECONDS = 30L;
    private static final int MAX_TERMINATION_ERROR_LENGTH = 2000;

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

    @Value("${careconnect.call.transcript.post-call-upload-grace-seconds:120}")
    private long transcriptUploadGraceSeconds = 120L;

    public record LeaveResult(
            boolean terminationOwner,
            boolean ended,
            long remainingParticipants,
            UUID terminationClaimId,
            List<Long> notifyUserIds) {
        public LeaveResult(
                final boolean terminationOwner,
                final boolean ended,
                final long remainingParticipants) {
            this(terminationOwner, ended, remainingParticipants, null, List.of());
        }
    }

    public record DeclineResult(
            List<Long> notifyUserIds, boolean terminationOwner, UUID terminationClaimId) {
        public DeclineResult(
                final List<Long> notifyUserIds, final boolean terminationOwner) {
            this(notifyUserIds, terminationOwner, null);
        }
    }

    public record TerminationClaim(
            String callId, UUID claimId, List<Long> notifyUserIds) {}

    /** Snapshot of independently fenced termination step completion. */
    public record TerminationProgress(
            boolean sentimentDone,
            boolean summaryDone,
            boolean recordingDone,
            boolean meetingDone) {
        public boolean isDone(final TerminationStep step) {
            return switch (step) {
                case SENTIMENT -> sentimentDone;
                case SUMMARY -> summaryDone;
                case RECORDING -> recordingDone;
                case MEETING -> meetingDone;
                case COMPLETE -> sentimentDone && summaryDone && recordingDone && meetingDone;
            };
        }

        public boolean allRequiredDone() {
            return isDone(TerminationStep.COMPLETE);
        }
    }

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
        final int inserted = callSessionRepository.insertIfAbsent(
                normalizedCallId,
                patient.getId(),
                creator.getId(),
                scheduledVisitId,
                SESSION_CREATED);
        final var stored = callSessionRepository.findByCallId(normalizedCallId);
        final CallSession session;
        final boolean newlyCreated;
        if (stored.isPresent()) {
            session = requireSameOwnership(
                    stored.get(), patient.getId(), creator.getId(), scheduledVisitId);
            newlyCreated = inserted == 1;
        } else {
            // Keeps isolated unit tests and non-PostgreSQL developer stores usable.
            // Production PostgreSQL takes the atomic INSERT ... ON CONFLICT path above.
            final CallSession created = new CallSession();
            created.setCallId(normalizedCallId);
            created.setPatientId(patient.getId());
            created.setCreatedByUserId(creator.getId());
            created.setScheduledVisitId(scheduledVisitId);
            created.setStatus(SESSION_CREATED);
            session = callSessionRepository.save(created);
            newlyCreated = true;
        }

        if (newlyCreated) {
            upsertParticipant(session, creator.getId(), creator.getId(), PARTICIPANT_INVITED);
            if (inviteeUserId != null) {
                final User invitee = userRepository.findById(inviteeUserId)
                        .orElseThrow(() -> new AppException(
                                HttpStatus.NOT_FOUND, "Invitee not found"));
                authorizeForPatient(invitee, patientUserId);
                upsertParticipant(
                        session, invitee.getId(), creator.getId(), PARTICIPANT_INVITED);
            }
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
        final boolean joinableParticipant = userId != null && callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .filter(participant -> PARTICIPANT_INVITED.equals(participant.getStatus())
                        || PARTICIPANT_JOINED.equals(participant.getStatus()))
                .isPresent();
        if (!joinableParticipant) {
            throw new AppException(HttpStatus.FORBIDDEN, "User is not authorized for this call");
        }
        return session;
    }

    /** Requires durable call membership for non-PHI signaling and telemetry attribution. */
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

    /** Requires durable PHI access earned by joining the call. */
    @Transactional(readOnly = true)
    public CallSession requireHistoricalParticipant(final String callId, final Long userId) {
        final CallSession session = requireSession(callId);
        final boolean hasHistoricalAccess = userId != null && callParticipantRepository
                .findByCallSessionIdAndUserId(session.getId(), userId)
                .filter(participant -> PARTICIPANT_JOINED.equals(participant.getStatus())
                        || PARTICIPANT_LEFT.equals(participant.getStatus())
                        || PARTICIPANT_EXPIRED.equals(participant.getStatus()))
                .isPresent();
        if (!hasHistoricalAccess) {
            throw new AppException(HttpStatus.FORBIDDEN, "User has no historical call access");
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
     * Allows a joined historical participant to finish durable transcript retries briefly after
     * call termination. The transcript purge fence is checked independently by the writer.
     *
     * <p>{@code TERMINATING} sessions are within grace even when {@code ended_at} is still null
     * (that timestamp is written only on {@code completeTermination}).
     */
    @Transactional(readOnly = true)
    public CallSession requireTranscriptUploadParticipant(
            final String callId, final Long userId) {
        final CallSession session = requireSession(callId);
        if (SESSION_CREATED.equals(session.getStatus())
                || SESSION_ACTIVE.equals(session.getStatus())) {
            return requireActiveParticipant(callId, userId);
        }
        requireHistoricalParticipant(callId, userId);
        if (SESSION_TERMINATING.equals(session.getStatus())) {
            return session;
        }
        final LocalDateTime endedAt = session.getEndedAt();
        final LocalDateTime deadline = endedAt == null
                ? null
                : endedAt.plusSeconds(Math.max(0L, transcriptUploadGraceSeconds));
        if (deadline == null || LocalDateTime.now(ZoneOffset.UTC).isAfter(deadline)) {
            throw new AppException(HttpStatus.GONE, "Transcript upload grace period has expired");
        }
        return session;
    }

    /**
     * Recording metadata/playback requires historical participation or a durable
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
        authorizeForPatient(user, requirePatientUserId(session));
        return session;
    }

    /**
     * Persists the Chime meeting id after a durable join has already succeeded.
     *
     * @param callId durable call identifier
     * @param meetingId Chime meeting id, ignored when blank
     */
    public void attachChimeMeetingId(final String callId, final String meetingId) {
        if (meetingId == null || meetingId.isBlank()) {
            return;
        }
        final CallSession session = callSessionRepository.findByCallId(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        callSessionRepository.activateIfJoinable(
                session.getId(), meetingId, SESSION_CREATED, SESSION_ACTIVE);
    }

    /**
     * Rolls back a durable JOINED mark when Chime attendee creation fails before credentials are
     * persisted. Also clears the recording-start election when fewer than two participants remain
     * joined so a later successful join can re-elect.
     */
    public void revertJoinAfterChimeFailure(final String callId, final Long userId) {
        final CallSession session = callSessionRepository.findByCallId(callId)
                .orElse(null);
        if (session == null || userId == null) {
            return;
        }
        final int reverted = callParticipantRepository.revertJoinedToInvitedWithoutAttendee(
                session.getId(), userId, PARTICIPANT_JOINED, PARTICIPANT_INVITED);
        if (reverted != 1) {
            return;
        }
        final long joined = callParticipantRepository.countByCallSessionIdAndStatus(
                session.getId(), PARTICIPANT_JOINED);
        if (joined < 2) {
            callSessionRepository.clearRecordingStartElected(session.getId());
        }
    }

    /**
     * Authorizes access using the patient entity id from historical call artifacts when no
     * durable session row exists.
     */
    @Transactional(readOnly = true)
    public void requirePatientEntityAccess(final User user, final Long patientEntityId) {
        if (user == null || user.getId() == null) {
            throw new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated");
        }
        if (user.getRole() == com.careconnect.security.Role.ADMIN) {
            return;
        }
        if (patientEntityId == null) {
            throw new AppException(HttpStatus.NOT_FOUND, "Call not found");
        }
        authorizeForPatient(user, requirePatientUserIdFromEntityId(patientEntityId));
    }

    private Long requirePatientUserIdFromEntityId(final Long patientEntityId) {
        final Patient patient = patientRepository.findById(patientEntityId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));
        if (patient.getUser() == null || patient.getUser().getId() == null) {
            throw new AppException(HttpStatus.NOT_FOUND, "Patient user not found");
        }
        return patient.getUser().getId();
    }

    public boolean recordJoin(
            final CallSession session, final Long userId, final String chimeMeetingId) {
        final CallSession locked = callSessionRepository.findByCallIdForLifecycle(session.getCallId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (callSessionRepository.activateIfJoinable(
                locked.getId(), chimeMeetingId, SESSION_CREATED, SESSION_ACTIVE) != 1
                || callParticipantRepository.markJoinedIfInvited(
                        locked.getId(), userId, PARTICIPANT_INVITED, PARTICIPANT_JOINED) != 1) {
            throw new AppException(HttpStatus.GONE, "Call is no longer joinable");
        }
        return callSessionRepository.electRecordingStart(
                locked.getId(), PARTICIPANT_JOINED, 2) == 1;
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
            if (!PARTICIPANT_JOINED.equals(participant.getStatus())
                    && !PARTICIPANT_LEFT.equals(participant.getStatus())) {
                throw new AppException(
                        HttpStatus.FORBIDDEN, "User must join the call before this operation");
            }
            return claimExistingTermination(session, userId);
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
        final List<Long> notifyUserIds = terminationRecipients(session.getId(), userId);
        final UUID claimId = UUID.randomUUID();
        final boolean owner = callSessionRepository.beginTermination(
                session.getId(),
                SESSION_CREATED,
                SESSION_ACTIVE,
                SESSION_TERMINATING,
                claimId,
                userId,
                leaseUntil(TERMINATION_LEASE_SECONDS),
                serializeUserIds(notifyUserIds)) == 1;
        return new LeaveResult(
                owner, false, remaining, owner ? claimId : null, owner ? notifyUserIds : List.of());
    }

    /**
     * Renews the termination lease when {@code claimId} still owns the session.
     *
     * @return progress snapshot when ownership is confirmed; {@code null} when stale
     */
    public TerminationProgress renewTerminationOwnership(
            final String callId, final UUID claimId) {
        if (claimId == null) {
            return null;
        }
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (!SESSION_TERMINATING.equals(session.getStatus())
                || !claimId.equals(session.getTerminationClaimId())) {
            return null;
        }
        if (callSessionRepository.renewTerminationLease(
                session.getId(),
                SESSION_TERMINATING,
                claimId,
                leaseUntil(TERMINATION_LEASE_SECONDS)) != 1) {
            return null;
        }
        final CallSession refreshed = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        return toProgress(refreshed);
    }

    /**
     * Verifies claim ownership without extending the lease.
     *
     * @return progress when still owner; {@code null} when stale
     */
    public TerminationProgress verifyTerminationOwnership(
            final String callId, final UUID claimId) {
        if (claimId == null) {
            return null;
        }
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (!SESSION_TERMINATING.equals(session.getStatus())
                || !claimId.equals(session.getTerminationClaimId())) {
            return null;
        }
        return toProgress(session);
    }

    /**
     * Token-fenced compare-and-set that records a completed termination step.
     *
     * @return {@code true} when this claim advanced the step
     */
    public boolean advanceTerminationStep(
            final String callId, final UUID claimId, final TerminationStep step) {
        if (claimId == null || step == null || step == TerminationStep.COMPLETE) {
            return false;
        }
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (!SESSION_TERMINATING.equals(session.getStatus())
                || !claimId.equals(session.getTerminationClaimId())) {
            return false;
        }
        final LocalDateTime lease = leaseUntil(TERMINATION_LEASE_SECONDS);
        final int advanced = switch (step) {
            case SENTIMENT -> callSessionRepository.markTerminationSentiment(
                    session.getId(), SESSION_TERMINATING, claimId, lease);
            case SUMMARY -> callSessionRepository.markTerminationSummary(
                    session.getId(), SESSION_TERMINATING, claimId, lease);
            case RECORDING -> callSessionRepository.markTerminationRecording(
                    session.getId(), SESSION_TERMINATING, claimId, lease);
            case MEETING -> callSessionRepository.markTerminationMeeting(
                    session.getId(), SESSION_TERMINATING, claimId, lease);
            case COMPLETE -> 0;
        };
        return advanced == 1;
    }

    public boolean completeTermination(final String callId, final UUID claimId) {
        if (claimId == null) {
            return false;
        }
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (callSessionRepository.renewTerminationLease(
                session.getId(),
                SESSION_TERMINATING,
                claimId,
                leaseUntil(TERMINATION_LEASE_SECONDS)) != 1) {
            return false;
        }
        final int completed = callSessionRepository.completeTermination(
                session.getId(), SESSION_TERMINATING, SESSION_ENDED, claimId);
        if (completed != 1) {
            return false;
        }
        callParticipantRepository.expireJoinedParticipants(
                session.getId(), PARTICIPANT_JOINED, PARTICIPANT_EXPIRED);
        return true;
    }

    public void recordTerminationFailure(
            final String callId, final UUID claimId, final Throwable failure) {
        if (claimId == null) {
            return;
        }
        recordTerminationRetry(callId, claimId, failureMessage(failure));
    }

    /** Parks a still-owned TERMINATING session for retry without clearing step progress. */
    public void recordTerminationRetry(
            final String callId, final UUID claimId, final String message) {
        if (claimId == null) {
            return;
        }
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        if (!SESSION_TERMINATING.equals(session.getStatus())
                || !claimId.equals(session.getTerminationClaimId())) {
            return;
        }
        callSessionRepository.failTermination(
                session.getId(),
                SESSION_TERMINATING,
                claimId,
                leaseUntil(TERMINATION_RETRY_SECONDS),
                truncateTerminationError(message));
    }

    public LeaveResult claimTerminationRetry(final String callId, final Long userId) {
        final CallSession session = callSessionRepository.findByCallIdForLifecycle(callId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Call session not found"));
        requireHistoricalParticipant(callId, userId);
        if (SESSION_ENDED.equals(session.getStatus()) || SESSION_CANCELLED.equals(session.getStatus())) {
            return new LeaveResult(false, true, 0);
        }
        if (!SESSION_TERMINATING.equals(session.getStatus())) {
            throw new AppException(HttpStatus.CONFLICT, "Call termination has not started");
        }
        return claimExistingTermination(session, userId);
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
        final long joined = callParticipantRepository.countByCallSessionIdAndStatus(
                session.getId(), PARTICIPANT_JOINED);
        final long invited = callParticipantRepository.countByCallSessionIdAndStatus(
                session.getId(), PARTICIPANT_INVITED);
        if (joined > 0 || invited > 0) {
            return new DeclineResult(notify, false, null);
        }
        if (SESSION_CREATED.equals(session.getStatus())) {
            callSessionRepository.cancelIfNotActive(
                    session.getId(), SESSION_CREATED, SESSION_CANCELLED);
            return new DeclineResult(notify, false, null);
        }
        final UUID claimId = UUID.randomUUID();
        final boolean terminationOwner = callSessionRepository.beginTermination(
                session.getId(),
                SESSION_CREATED,
                SESSION_ACTIVE,
                SESSION_TERMINATING,
                claimId,
                userId,
                leaseUntil(TERMINATION_LEASE_SECONDS),
                serializeUserIds(notify)) == 1;
        return new DeclineResult(notify, terminationOwner, terminationOwner ? claimId : null);
    }

    @Transactional(readOnly = true)
    public List<Long> findDueTerminationIds(final int limit) {
        return callSessionRepository.findDueTerminationIds(
                SESSION_TERMINATING, Math.max(1, limit));
    }

    public TerminationClaim claimDueTermination(final Long sessionId) {
        final CallSession session = callSessionRepository.findByIdForLifecycle(sessionId)
                .orElse(null);
        if (session == null || !SESSION_TERMINATING.equals(session.getStatus())) {
            return null;
        }
        final LeaveResult claim = claimExistingTermination(session, null);
        if (!claim.terminationOwner()) {
            return null;
        }
        return new TerminationClaim(
                session.getCallId(), claim.terminationClaimId(), claim.notifyUserIds());
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

    private TerminationProgress toProgress(final CallSession session) {
        return new TerminationProgress(
                session.getTerminationSentimentAt() != null,
                session.getTerminationSummaryAt() != null,
                session.getTerminationRecordingAt() != null,
                session.getTerminationMeetingAt() != null);
    }

    private String failureMessage(final Throwable failure) {
        if (failure == null) {
            return "Unknown termination failure";
        }
        final String message = failure.getMessage();
        if (message == null || message.isBlank()) {
            return failure.getClass().getSimpleName();
        }
        return message;
    }

    private String truncateTerminationError(final String message) {
        if (message == null || message.isBlank()) {
            return "Unknown termination failure";
        }
        if (message.length() > MAX_TERMINATION_ERROR_LENGTH) {
            return message.substring(0, MAX_TERMINATION_ERROR_LENGTH);
        }
        return message;
    }

    private static LocalDateTime leaseUntil(final long seconds) {
        return LocalDateTime.now(ZoneOffset.UTC).plusSeconds(seconds);
    }

    private LeaveResult claimExistingTermination(
            final CallSession session, final Long claimedByUserId) {
        final UUID claimId = UUID.randomUUID();
        final boolean owner = callSessionRepository.reclaimTermination(
                session.getId(),
                SESSION_TERMINATING,
                claimId,
                claimedByUserId,
                leaseUntil(TERMINATION_LEASE_SECONDS)) == 1;
        final List<Long> notifyUserIds =
                deserializeUserIds(session.getTerminationNotifyUserIds());
        return new LeaveResult(
                owner, false, 0, owner ? claimId : null, notifyUserIds);
    }

    private List<Long> terminationRecipients(
            final Long sessionId, final Long actorUserId) {
        return callParticipantRepository.findByCallSessionId(sessionId).stream()
                .filter(p -> !Objects.equals(p.getUserId(), actorUserId))
                .filter(p -> PARTICIPANT_INVITED.equals(p.getStatus())
                        || PARTICIPANT_JOINED.equals(p.getStatus())
                        || PARTICIPANT_LEFT.equals(p.getStatus()))
                .map(CallParticipant::getUserId)
                .distinct()
                .sorted()
                .toList();
    }

    private String serializeUserIds(final List<Long> userIds) {
        return userIds.stream().map(String::valueOf).collect(java.util.stream.Collectors.joining(","));
    }

    private List<Long> deserializeUserIds(final String serialized) {
        if (serialized == null || serialized.isBlank()) {
            return List.of();
        }
        return java.util.Arrays.stream(serialized.split(","))
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .map(Long::valueOf)
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
            final String existingStatus = existing.get().getStatus();
            if (PARTICIPANT_INVITED.equals(initialStatus)
                    && (PARTICIPANT_LEFT.equals(existingStatus)
                            || PARTICIPANT_DECLINED.equals(existingStatus))) {
                callParticipantRepository.reinviteIfInactive(
                        session.getId(),
                        userId,
                        invitedByUserId,
                        PARTICIPANT_INVITED,
                        PARTICIPANT_LEFT,
                        PARTICIPANT_DECLINED);
                return callParticipantRepository
                        .findByCallSessionIdAndUserId(session.getId(), userId)
                        .orElseThrow();
            }
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
