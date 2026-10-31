package com.careconnect.repository;

import com.careconnect.model.FriendRequest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@ActiveProfiles("test")
@DisplayName("FriendRequestRepository.existsAcceptedBetween")
class FriendRequestRepositoryTest {

    @Autowired
    private FriendRequestRepository repository;
    @Autowired
    private TestEntityManager entityManager;

    private void request(final long from, final long to, final String status) {
        final FriendRequest request = new FriendRequest();
        request.setFromUserId(from);
        request.setToUserId(to);
        request.setStatus(status);
        entityManager.persistAndFlush(request);
    }

    @Test
    @DisplayName("TC-MSG-POL-008 an accepted request makes the two users friends, whichever way it was sent")
    void accepted_eitherDirection_true() {
        request(1, 2, "accepted");

        assertThat(repository.existsAcceptedBetween(1L, 2L)).isTrue();
        assertThat(repository.existsAcceptedBetween(2L, 1L)).isTrue();
    }

    @Test
    @DisplayName("TC-MSG-POL-009 a pending or rejected request does not")
    void pendingOrRejected_false() {
        request(1, 2, "pending");
        request(3, 4, "rejected");

        assertThat(repository.existsAcceptedBetween(1L, 2L)).isFalse();
        assertThat(repository.existsAcceptedBetween(3L, 4L)).isFalse();
    }

    @Test
    @DisplayName("TC-MSG-POL-010 an accepted request between other users does not")
    void acceptedBetweenOthers_false() {
        request(1, 2, "accepted");

        assertThat(repository.existsAcceptedBetween(1L, 3L)).isFalse();
        assertThat(repository.existsAcceptedBetween(3L, 2L)).isFalse();
    }
}
