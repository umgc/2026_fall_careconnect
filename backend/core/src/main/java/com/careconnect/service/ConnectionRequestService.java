package com.careconnect.service;

import com.careconnect.model.ConnectionRequest;
import com.careconnect.model.User;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.repository.ConnectionRequestRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.service.EmailService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class ConnectionRequestService {
    private final ConnectionRequestRepository connectionRequestRepo;
    private final UserRepository userRepo;
    private final CaregiverPatientLinkRepository linkRepo;
    private final EmailService emailService;

    @Autowired(required = false)
    private NotificationService notificationService;

    @Value("${frontend.base-url:http://localhost:3000}")
    private String frontendBaseUrl;

    /**
     * Create a connection request from a caregiver to a patient
     */
    @Transactional
    public ConnectionRequest createRequest(Long caregiverId, String patientEmail,
                                           String relationshipType, String message) {
        // Find caregiver and patient
        User caregiver = userRepo.findById(caregiverId)
                .orElseThrow(() -> new IllegalArgumentException("Caregiver not found"));

        User patient = userRepo.findByEmail(patientEmail)
                .orElseThrow(() -> new IllegalArgumentException("Patient not found with email: " + patientEmail));

        // Check if there's already a pending request
        if (connectionRequestRepo.existsByCaregiverAndPatientAndStatus(caregiver, patient, "PENDING")) {
            throw new IllegalStateException("There's already a pending connection request to this patient");
        }

        // Create request
        ConnectionRequest request = ConnectionRequest.builder()
                .caregiver(caregiver)
                .patient(patient)
                .status("PENDING")
                .relationshipType(relationshipType)
                .message(message)
                .requestedAt(Instant.now())
                .token(UUID.randomUUID().toString())
                .build();

        connectionRequestRepo.save(request);

        // Send email to patient
        sendConnectionRequestEmail(request);

        // Send Firebase notification to patient about connection request
        try {
            if (notificationService != null) {
                notificationService.sendNotificationToUser(
                        patient.getId(),
                        "🔗 New Connection Request",
                        String.format("%s would like to connect with you as your caregiver", caregiver.getName()),
                        "CONNECTION_REQUEST",
                        Map.of(
                                "type", "CONNECTION_REQUEST",
                                "caregiverName", caregiver.getName(),
                                "caregiverId", caregiver.getId().toString(),
                                "relationshipType", relationshipType,
                                "requestToken", request.getToken(),
                                "requestedAt", request.getRequestedAt().toString()
                        )
                );
            }
        } catch (Exception e) {
            // Log but don't fail the request creation if notification fails
            System.err.println("Failed to send connection request notification: " + e.getMessage());
        }

        return request;
    }

    /**
     * Process a patient's response to a connection request
     */
    @Transactional
    public void processResponse(String token, boolean accepted) {
        ConnectionRequest request = connectionRequestRepo.findByToken(token)
                .orElseThrow(() -> new IllegalArgumentException("Invalid request token"));

        if (!"PENDING".equals(request.getStatus())) {
            throw new IllegalStateException("This request has already been processed");
        }

        request.setRespondedAt(Instant.now());
        request.setStatus(accepted ? "ACCEPTED" : "REJECTED");
        connectionRequestRepo.save(request);

        // If accepted, create caregiver-patient link
        if (accepted) {
            createCaregiverPatientLink(request);

            // Send Firebase notification to caregiver about acceptance
            try {
                if (notificationService != null) {
                    notificationService.sendNotificationToUser(
                            request.getCaregiver().getId(),
                            "✅ Connection Request Accepted",
                            String.format("%s has accepted your connection request! You are now connected.",
                                    request.getPatient().getName()),
                            "CONNECTION_ACCEPTED",
                            Map.of(
                                    "type", "CONNECTION_ACCEPTED",
                                    "patientName", request.getPatient().getName(),
                                    "patientId", request.getPatient().getId().toString(),
                                    "relationshipType", request.getRelationshipType() != null ? request.getRelationshipType() : "Caregiver",
                                    "acceptedAt", request.getRespondedAt().toString()
                            )
                    );
                }
            } catch (Exception e) {
                // Log but don't fail the acceptance if notification fails
                System.err.println("Failed to send connection acceptance notification: " + e.getMessage());
            }
        }

        // Send notification to caregiver
        sendResponseNotificationEmail(request);
    }

    /**
     * Create caregiver-patient link
     */
    private void createCaregiverPatientLink(ConnectionRequest request) {
        CaregiverPatientLink link = new CaregiverPatientLink(
                request.getCaregiver(),
                request.getPatient(),
                request.getCaregiver(),
                CaregiverPatientLink.LinkType.PERMANENT
        );
        link.setStatus(CaregiverPatientLink.LinkStatus.ACTIVE);
        link.setNotes(request.getRelationshipType());

        linkRepo.save(link);
    }

    /**
     * Send email to patient with connection request
     */
    private void sendConnectionRequestEmail(ConnectionRequest request) {
        User caregiver = request.getCaregiver();
        User patient = request.getPatient();

        String subject = "CareConnect: Connection Request from " + caregiver.getName();
        // Use frontend base URL from application properties
        String baseUrl = frontendBaseUrl;

        String emailBody = String.format(
                "<div style=\"font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;\">\n" +
                        "    <h2 style=\"color: #2c3e50; text-align: center;\">CareConnect Connection Request</h2>\n" +
                        "    \n" +
                        "    <p style=\"font-size: 16px; line-height: 1.6; color: #333;\">\n" +
                        "        Hello %s,\n" +
                        "    </p>\n" +
                        "    \n" +
                        "    <p style=\"font-size: 16px; line-height: 1.6; color: #333;\">\n" +
                        "        %s would like to connect with you on CareConnect as your caregiver.\n" +
                        "    </p>\n" +
                        "    \n" +
                        "    %s\n" +
                        "    \n" +
                        "    <div style=\"text-align: center; margin: 30px 0;\">\n" +
                        "        <a href=\"%s/approve-connection?token=%s\" \n" +
                        "           style=\"background-color: #2ecc71; \n" +
                        "                  color: white; \n" +
                        "                  padding: 10px 20px; \n" +
                        "                  text-decoration: none; \n" +
                        "                  border-radius: 5px; \n" +
                        "                  font-weight: bold; \n" +
                        "                  margin-right: 10px;\">\n" +
                        "            Approve\n" +
                        "        </a>\n" +
                        "        \n" +
                        "        <a href=\"%s/reject-connection?token=%s\" \n" +
                        "           style=\"background-color: #e74c3c; \n" +
                        "                  color: white; \n" +
                        "                  padding: 10px 20px; \n" +
                        "                  text-decoration: none; \n" +
                        "                  border-radius: 5px; \n" +
                        "                  font-weight: bold;\">\n" +
                        "            Reject\n" +
                        "        </a>\n" +
                        "    </div>\n" +
                        "    \n" +
                        "    <p style=\"font-size: 14px; color: #666; text-align: center;\">\n" +
                        "        If you didn't expect this connection request, you can safely ignore it.\n" +
                        "    </p>\n" +
                        "    \n" +
                        "    <hr style=\"border: none; border-top: 1px solid #eee; margin: 30px 0;\">\n" +
                        "    \n" +
                        "    <p style=\"font-size: 12px; color: #999; text-align: center;\">\n" +
                        "        This is an automated message from CareConnect. Please do not reply to this email.\n" +
                        "    </p>\n" +
                        "</div>\n",
                patient.getName(),
                caregiver.getName(),
                request.getMessage() != null && !request.getMessage().isEmpty() ?
                        "<p style=\"font-size: 16px; line-height: 1.6; color: #333; font-style: italic;\">" +
                                "\"" + request.getMessage() + "\"</p>" : "",
                baseUrl,
                request.getToken(),
                baseUrl,
                request.getToken()
        );

        emailService.sendHtmlEmail(patient.getEmail(), subject, emailBody, "html");
    }

    /**
     * Send notification email to caregiver about patient's response
     */
    private void sendResponseNotificationEmail(ConnectionRequest request) {
        User caregiver = request.getCaregiver();
        User patient = request.getPatient();
        boolean accepted = "ACCEPTED".equals(request.getStatus());

        String subject = "CareConnect: Connection Request " +
                (accepted ? "Accepted" : "Declined") +
                " by " + patient.getName();

        String emailBody = String.format(
                "<div style=\"font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;\">\n" +
                        "    <h2 style=\"color: #2c3e50; text-align: center;\">Connection Request %s</h2>\n" +
                        "    \n" +
                        "    <p style=\"font-size: 16px; line-height: 1.6; color: #333;\">\n" +
                        "        Hello %s,\n" +
                        "    </p>\n" +
                        "    \n" +
                        "    <p style=\"font-size: 16px; line-height: 1.6; color: #333;\">\n" +
                        "        %s has %s your connection request on CareConnect.\n" +
                        "    </p>\n" +
                        "    \n" +
                        "    %s\n" +
                        "    \n" +
                        "    <hr style=\"border: none; border-top: 1px solid #eee; margin: 30px 0;\">\n" +
                        "    \n" +
                        "    <p style=\"font-size: 12px; color: #999; text-align: center;\">\n" +
                        "        This is an automated message from CareConnect. Please do not reply to this email.\n" +
                        "    </p>\n" +
                        "</div>\n",
                accepted ? "Accepted" : "Declined",
                caregiver.getName(),
                patient.getName(),
                accepted ? "accepted" : "declined",
                accepted ?
                        "<p style=\"font-size: 16px; line-height: 1.6; color: #333;\">You can now see and manage their care through the CareConnect platform.</p>" :
                        "<p style=\"font-size: 16px; line-height: 1.6; color: #333;\">If you believe this was a mistake, you may send another request at a later time.</p>"
        );

        emailService.sendHtmlEmail(caregiver.getEmail(), subject, emailBody, "html");
    }

    /**
     * Get pending requests for a patient
     */
    public List<ConnectionRequest> getPendingRequestsForPatient(Long patientId) {
        User patient = userRepo.findById(patientId)
                .orElseThrow(() -> new IllegalArgumentException("Patient not found"));

        return connectionRequestRepo.findByPatientAndStatus(patient, "PENDING");
    }

    /**
     * Get pending requests sent by a caregiver
     */
    public List<ConnectionRequest> getPendingRequestsByCaregiver(Long caregiverId) {
        User caregiver = userRepo.findById(caregiverId)
                .orElseThrow(() -> new IllegalArgumentException("Caregiver not found"));

        return connectionRequestRepo.findByCaregiverAndStatus(caregiver, "PENDING");
    }
}