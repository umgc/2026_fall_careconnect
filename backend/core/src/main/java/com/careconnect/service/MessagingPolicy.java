package com.careconnect.service;

import com.careconnect.repository.FriendRequestRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Who may send a direct message to whom. One rule for every way a message is sent: the REST
 * {@code /v1/api/messages/send} and {@code /send-attachment} endpoints and the {@code /ws/chat}
 * WebSocket.
 *
 * <p>Chat is opened from two places, so two relationships allow it:
 * <ul>
 *   <li>A caregiver and a patient with an active link. The link's messaging switch decides, in
 *       both directions: when the caregiver turns messaging off, neither side can send.</li>
 *   <li>Two users with an accepted friend request, in either direction (the Friends screen).</li>
 * </ul>
 * A caregiver-patient link takes precedence: a pair whose link has messaging off cannot get round
 * it by also being friends.
 */
@Service
@RequiredArgsConstructor
public class MessagingPolicy {

    /** What every refusal says, over REST and the chat socket alike. */
    public static final String NOT_ALLOWED = "You can't send messages to this user.";

    private final CaregiverPatientLinkService linkService;
    private final FriendRequestRepository friendRequests;

    /**
     * @return true when {@code senderUserId} may send a message to {@code receiverUserId}
     */
    @Transactional(readOnly = true)
    public boolean canMessage(final Long senderUserId, final Long receiverUserId) {
        if (senderUserId == null || receiverUserId == null || senderUserId.equals(receiverUserId)) {
            return false;
        }

        final boolean senderCaresForReceiver = linkService.hasAccessToPatient(senderUserId, receiverUserId);
        final boolean receiverCaresForSender = linkService.hasAccessToPatient(receiverUserId, senderUserId);
        if (senderCaresForReceiver || receiverCaresForSender) {
            return (senderCaresForReceiver && linkService.isPatientMessagingEnabled(senderUserId, receiverUserId))
                    || (receiverCaresForSender && linkService.isPatientMessagingEnabled(receiverUserId, senderUserId));
        }

        return friendRequests.existsAcceptedBetween(senderUserId, receiverUserId);
    }
}
