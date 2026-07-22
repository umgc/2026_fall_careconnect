package com.careconnect.service;

import com.careconnect.model.CallAttendee;
import com.careconnect.repository.CallAttendeeRepository;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Persists Chime attendee roster rows for speaker identification. */
@Service
public class CallAttendeeService {

    private final CallAttendeeRepository callAttendeeRepository;

    public CallAttendeeService(final CallAttendeeRepository callAttendeeRepository) {
        this.callAttendeeRepository = callAttendeeRepository;
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
}
