package com.careconnect.repository;

import com.careconnect.model.CallAttendee;
import java.time.LocalDateTime;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@DataJpaTest
@ActiveProfiles("test")
@DisplayName("CallAttendeeRepository Tests")
class CallAttendeeRepositoryTest {

    private static final String CALL_ID = "call-repo-001";

    @Autowired
    private CallAttendeeRepository repository;

    @Test
    @DisplayName("SPEAKER-007: save and find by callId and chimeAttendeeId")
    void saveAndFindByCallIdAndChimeAttendeeId() {
        final CallAttendee attendee = buildAttendee("att-1", 1L, "CAREGIVER");
        repository.saveAndFlush(attendee);

        assertThat(repository.findByCallIdAndChimeAttendeeId(CALL_ID, "att-1"))
                .isPresent()
                .get()
                .satisfies(
                        row -> {
                            assertThat(row.getUserId()).isEqualTo(1L);
                            assertThat(row.getRole()).isEqualTo("CAREGIVER");
                            assertThat(row.getJoinedAt()).isNotNull();
                        });
    }

    @Test
    @DisplayName("SPEAKER-008: duplicate (call_id, chime_attendee_id) violates unique constraint")
    void duplicateCallIdAndChimeAttendeeId_throws() {
        repository.saveAndFlush(buildAttendee("att-dup", 1L, "CAREGIVER"));

        assertThatThrownBy(() -> repository.saveAndFlush(buildAttendee("att-dup", 2L, "PATIENT")))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("SPEAKER-009: findByCallIdAndUserIdAndLeftAtIsNull returns only active rows")
    void findActiveByUser_excludesLeftRows() {
        final CallAttendee active = buildAttendee("att-active", 5L, "PATIENT");
        repository.saveAndFlush(active);

        final CallAttendee left = buildAttendee("att-left", 5L, "PATIENT");
        left.setLeftAt(LocalDateTime.now());
        repository.saveAndFlush(left);

        assertThat(repository.findByCallIdAndUserIdAndLeftAtIsNull(CALL_ID, 5L))
                .hasSize(1)
                .first()
                .extracting(CallAttendee::getChimeAttendeeId)
                .isEqualTo("att-active");
    }

    private static CallAttendee buildAttendee(
            final String chimeAttendeeId, final Long userId, final String role) {
        final CallAttendee attendee = new CallAttendee();
        attendee.setCallId(CALL_ID);
        attendee.setChimeAttendeeId(chimeAttendeeId);
        attendee.setUserId(userId);
        attendee.setRole(role);
        attendee.setJoinedAt(LocalDateTime.now());
        return attendee;
    }
}
