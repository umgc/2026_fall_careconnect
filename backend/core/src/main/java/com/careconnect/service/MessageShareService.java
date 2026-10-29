package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.Message;
import com.careconnect.model.Message.ShareKind;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.Locale;

import static com.careconnect.model.Message.ShareKind.MEDICARE;

/**
 * A patient shares one kind of their data with a linked caregiver as a card in chat.
 *
 * <p>The card is a message that holds only what it opens ({@link ShareKind} and the
 * {@code patient.id}), never the data, and it grants nothing. When the caregiver opens it, the
 * data's own access rule decides, as for any other read: for Medicare, {@link MedicareAccessPolicy}
 * (an active link and the patient's {@code MEDICARE_VIEW} consent), so revoking consent also stops
 * every card already sent; for Health, the active caregiver link the Health tab's endpoints check.
 *
 * <p>Only a patient shares, only their own data, and only with a caregiver linked to them with
 * messaging on. The patient record comes from the signed-in user, never from the request.
 */
@Service
@RequiredArgsConstructor
public class MessageShareService {

    static final String ONLY_PATIENT = "Only a patient can share their records.";
    static final String UNKNOWN_KIND = "Unknown share kind.";
    static final String NO_RECEIVER = "receiverId is required.";
    static final String CONNECT_MEDICARE = "Connect Medicare before sharing it.";

    private final MessageRepository messages;
    private final PatientRepository patients;
    private final UserRepository users;
    private final CaregiverPatientLinkService linkService;
    private final MessagingPolicy messagingPolicy;
    private final MedicareAccessPolicy medicareAccess;
    private final ChatMessageWebSocketHandler chatSocket;
    private final MedicareConnectionService medicareConnectionService;
    private final MedicareProperties medicareProperties;

    /**
     * @param message         the saved card
     * @param receiverCanView whether the caregiver can open it now. False means the patient has not
     *                        given the consent yet, so the app offers to share.
     */
    public record ShareResult(Message message, boolean receiverCanView) {
    }

    /**
     * Saves the card, pushes it to the caregiver once it is committed if they are connected to chat,
     * and says whether they can open it yet.
     *
     * @param sender     the signed-in user, never a value the client supplied
     * @param receiverId the caregiver's user id
     * @param kind       a {@link ShareKind} name, case-insensitive
     * @throws AppException 403 if the sender is not a patient or may not share with this receiver,
     *                      400 for a missing receiver or an unknown kind
     *                      409 for a MEDICARE card when the patient has not connected Medicare (in mock
     *                      mode every patient counts as connected, as on the Medicare tile)
     */
    @Transactional
    public ShareResult share(final User sender, final Long receiverId, final String kind) {
        if (sender == null || sender.getId() == null || !sender.isPatient()) {
            throw new AppException(HttpStatus.FORBIDDEN, ONLY_PATIENT);
        }
        final ShareKind shareKind = parseKind(kind);
        if (receiverId == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, NO_RECEIVER);
        }
        final Patient patient = patients.findByUserId(sender.getId())
                .orElseThrow(() -> new AppException(HttpStatus.FORBIDDEN, ONLY_PATIENT));

        // Only a caregiver linked to this patient, and only while the link allows messaging. A friend
        // can message the patient but cannot receive a share card.
        if (!linkService.hasAccessToPatient(receiverId, sender.getId())
                || !messagingPolicy.canMessage(sender.getId(), receiverId)) {
            throw new AppException(HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
        }

        // A MEDICARE card needs Medicare connected, or the caregiver opens an empty tab. Mock mode is
        // decided here, as MedicareConnectionController.status does: the connection service only reads
        // the saved crosswalk, which mock mode never writes.
        if (shareKind == MEDICARE && !medicareProperties.isMock()
                && !medicareConnectionService.status(patient.getId()).connected()) {
            throw new AppException(HttpStatus.CONFLICT, CONNECT_MEDICARE);
        }

        // Everything that can still fail runs before the card is saved
        final User receiver = users.findById(receiverId).orElse(null);
        final boolean receiverCanView = canView(receiver, shareKind, patient.getId());

        final Message card = new Message(sender.getId(), receiverId, fallbackText(shareKind));
        card.setShareKind(shareKind);
        card.setSharePatientId(patient.getId());
        final Message saved = messages.save(card);
        deliverAfterCommit(saved);
        return new ShareResult(saved, receiverCanView);
    }

    /**
     * Pushes the card only once it is committed, so a rollback never leaves the caregiver holding a
     * card that does not exist, and a caregiver who reloads the conversation on the push finds it.
     * Without a transaction (a caller outside Spring's), the card is already saved, so it goes now.
     */
    private void deliverAfterCommit(final Message saved) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            chatSocket.deliver(saved);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                chatSocket.deliver(saved);
            }
        });
    }

    private static ShareKind parseKind(final String kind) {
        if (kind == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, UNKNOWN_KIND);
        }
        try {
            return ShareKind.valueOf(kind.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new AppException(HttpStatus.BAD_REQUEST, UNKNOWN_KIND);
        }
    }

    private boolean canView(final User receiver, final ShareKind kind, final Long patientId) {
        return switch (kind) {
            case MEDICARE -> medicareAccess.canAccess(receiver, patientId);
            // The Health tab's reads (risks, symptoms, medications) admit any caregiver with an active
            // link, which share() has already required of the receiver
            case HEALTH -> true;
        };
    }

    /**
     * The card's text, which an app that does not know share cards shows as a plain message, and
     * which the inbox uses as the conversation's preview.
     */
    static String fallbackText(final ShareKind kind) {
        return switch (kind) {
            case MEDICARE -> "Shared my Medicare records";
            case HEALTH -> "Shared my health information";
        };
    }
}
