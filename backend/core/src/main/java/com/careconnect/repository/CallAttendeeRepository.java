package com.careconnect.repository;

import com.careconnect.model.CallAttendee;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface CallAttendeeRepository extends JpaRepository<CallAttendee, Long> {

    /**
     * Returns the attendee row for a call and Chime attendee id.
     *
     * @param callId call identifier
     * @param chimeAttendeeId Chime attendee UUID
     * @return matching row when present
     */
    Optional<CallAttendee> findByCallIdAndChimeAttendeeId(String callId, String chimeAttendeeId);

    /**
     * Returns active (not left) attendee rows for a call and user.
     *
     * @param callId call identifier
     * @param userId user identifier
     * @return matching active rows
     */
    List<CallAttendee> findByCallIdAndUserIdAndLeftAtIsNull(String callId, Long userId);

    /**
     * Returns all attendee rows for a call.
     *
     * @param callId call identifier
     * @return attendee rows for the call
     */
    List<CallAttendee> findByCallId(String callId);
}
