package com.careconnect.service;

import com.careconnect.model.CallAttendee;
import com.careconnect.repository.CallAttendeeRepository;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Persists Chime attendee roster rows for speaker identification. */
@Service
public class CallAttendeeService {

    private static final Logger log = LoggerFactory.getLogger(CallAttendeeService.class);

    private final CallAttendeeRepository callAttendeeRepository;
    private final ChimeService chimeService;

    public CallAttendeeService(
            final CallAttendeeRepository callAttendeeRepository, final ChimeService chimeService) {
        this.callAttendeeRepository = callAttendeeRepository;
        this.chimeService = chimeService;
    }

    /**
     * Upserts an attendee row when a user joins a call.
     * Re-join clears {@code left_at} and refreshes join metadata.
     */
    @Transactional
    public CallAttendee recordJoin(
            final String callId,
            final String chimeAttendeeId,
            final Long userId,
            final String role) {
        markSupersededAttendeeRows(callId, userId, chimeAttendeeId);
        final LocalDateTime now = LocalDateTime.now();
        return callAttendeeRepository
                .findByCallIdAndChimeAttendeeId(callId, chimeAttendeeId)
                .map(
                        existing -> {
                            existing.setUserId(userId);
                            existing.setRole(role);
                            existing.setJoinedAt(now);
                            existing.setLeftAt(null);
                            return callAttendeeRepository.save(existing);
                        })
                .orElseGet(
                        () -> {
                            final CallAttendee attendee = new CallAttendee();
                            attendee.setCallId(callId);
                            attendee.setChimeAttendeeId(chimeAttendeeId);
                            attendee.setUserId(userId);
                            attendee.setRole(role);
                            attendee.setJoinedAt(now);
                            return callAttendeeRepository.save(attendee);
                        });
    }

    /**
     * Authoritative upsert from EventBridge {@code MediaPipelineKinesisVideoStreamStart} when
     * {@code externalUserId} is an app-encoded id (not {@code aws:MediaPipeline-*}).
     */
    @Transactional
    public void recordJoinFromStreamEvent(
            final String callId, final String chimeAttendeeId, final String externalUserId) {
        if (ChimeExternalUserIdParser.isPipelineInternal(externalUserId)) {
            return;
        }
        final Long userId = ChimeExternalUserIdParser.parseUserId(externalUserId);
        if (userId == null) {
            return;
        }
        final String role = ChimeExternalUserIdParser.parseRole(externalUserId);
        recordJoin(callId, chimeAttendeeId, userId, role);
        if (log.isInfoEnabled()) {
            log.info(
                    "Roster upsert from EventBridge callId={} userId={} chimeAttendeeId={}"
                            + " externalUserId={}",
                    callId,
                    userId,
                    chimeAttendeeId,
                    externalUserId);
        }
    }

    /**
     * Syncs {@code call_attendees} from Chime {@code ListAttendees} — authoritative for live
     * {@code chime_attendee_id} values (O1 re-join / cache drift).
     */
    @Transactional
    public void reconcileRosterFromChime(final String callId, final String meetingId) {
        if (callId == null
                || callId.isBlank()
                || meetingId == null
                || meetingId.isBlank()) {
            return;
        }

        final List<ChimeMeetingAttendee> live = chimeService.listMeetingAttendees(meetingId);
        if (live.isEmpty()) {
            return;
        }

        final Set<String> liveAppAttendeeIds = new HashSet<>();
        for (final ChimeMeetingAttendee attendee : live) {
            if (attendee.attendeeId() == null
                    || attendee.attendeeId().isBlank()
                    || ChimeExternalUserIdParser.isPipelineInternal(attendee.externalUserId())) {
                continue;
            }
            final Long userId = ChimeExternalUserIdParser.parseUserId(attendee.externalUserId());
            if (userId == null) {
                continue;
            }
            liveAppAttendeeIds.add(attendee.attendeeId());
            final String role = ChimeExternalUserIdParser.parseRole(attendee.externalUserId());
            recordJoin(callId, attendee.attendeeId(), userId, role);
        }

        if (liveAppAttendeeIds.isEmpty()) {
            return;
        }

        final LocalDateTime now = LocalDateTime.now();
        final List<CallAttendee> activeRows =
                callAttendeeRepository.findByCallIdAndLeftAtIsNull(callId);
        for (final CallAttendee row : activeRows) {
            if (!liveAppAttendeeIds.contains(row.getChimeAttendeeId())) {
                row.setLeftAt(now);
                if (log.isInfoEnabled()) {
                    log.info(
                            "Marked call_attendees row left after Chime reconcile callId={}"
                                    + " chimeAttendeeId={} userId={}",
                            callId,
                            row.getChimeAttendeeId(),
                            row.getUserId());
                }
            }
        }
        if (!activeRows.isEmpty()) {
            callAttendeeRepository.saveAll(activeRows);
        }
    }

    /** Active roster Chime attendee ids for a call ({@code left_at} null). */
    public List<String> findActiveChimeAttendeeIds(final String callId) {
        return callAttendeeRepository.findByCallIdAndLeftAtIsNull(callId).stream()
                .map(CallAttendee::getChimeAttendeeId)
                .toList();
    }

    /** Persists the KVS stream ARN assigned to an attendee so post-call F7 can export it. */
    @Transactional
    public void recordKvsStreamMapping(
            final String callId, final String chimeAttendeeId, final String streamArn) {
        if (callId == null
                || callId.isBlank()
                || chimeAttendeeId == null
                || chimeAttendeeId.isBlank()
                || streamArn == null
                || streamArn.isBlank()) {
            return;
        }
        callAttendeeRepository
                .findByCallIdAndChimeAttendeeId(callId, chimeAttendeeId)
                .ifPresent(
                        attendee -> {
                            attendee.setKvsStreamArn(streamArn);
                            callAttendeeRepository.save(attendee);
                        });
    }

    /** Marks active attendee rows for the user as left on call end/leave. */
    @Transactional
    public void recordLeave(final String callId, final Long userId) {
        final LocalDateTime now = LocalDateTime.now();
        final List<CallAttendee> activeRows =
                callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(callId, userId);
        for (final CallAttendee row : activeRows) {
            row.setLeftAt(now);
        }
        if (!activeRows.isEmpty()) {
            callAttendeeRepository.saveAll(activeRows);
        }
    }

    private void markSupersededAttendeeRows(
            final String callId, final Long userId, final String chimeAttendeeId) {
        final LocalDateTime now = LocalDateTime.now();
        final List<CallAttendee> activeRows =
                callAttendeeRepository.findByCallIdAndUserIdAndLeftAtIsNull(callId, userId);
        boolean changed = false;
        for (final CallAttendee row : activeRows) {
            if (!chimeAttendeeId.equals(row.getChimeAttendeeId())) {
                row.setLeftAt(now);
                changed = true;
                if (log.isInfoEnabled()) {
                    log.info(
                            "Superseded stale chime_attendee_id callId={} userId={} old={} new={}",
                            callId,
                            userId,
                            row.getChimeAttendeeId(),
                            chimeAttendeeId);
                }
            }
        }
        if (changed) {
            callAttendeeRepository.saveAll(activeRows);
        }
    }
}
