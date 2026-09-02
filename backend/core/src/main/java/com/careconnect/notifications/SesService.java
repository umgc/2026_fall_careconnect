package com.careconnect.notifications;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.Body;
import software.amazon.awssdk.services.ses.model.Content;
import software.amazon.awssdk.services.ses.model.Destination;
import software.amazon.awssdk.services.ses.model.Message;
import software.amazon.awssdk.services.ses.model.SendEmailRequest;
import software.amazon.awssdk.services.ses.model.SendEmailResponse;

import java.util.List;

@Service
public class SesService {

    private final SesClient sesClient;
    private final String fromAddress;

    @Autowired
    public SesService(@Value("${aws.region:us-east-1}") String awsRegion,
                      @Value("${aws.ses.from:no-reply@careconnect.com}") String fromAddress) {
        Region region = Region.of(awsRegion);
        this.sesClient = SesClient.builder().region(region).build();
        this.fromAddress = fromAddress;
    }

    // Package-visible constructor for tests or alternate client injection
    SesService(SesClient sesClient, String fromAddress) {
        this.sesClient = sesClient;
        this.fromAddress = fromAddress;
    }

    /**
     * Send a basic email with HTML and text content
     */
    public String sendEmail(String toAddress, String subject, String htmlBody, String textBody) {
        Destination destination = Destination.builder().toAddresses(toAddress).build();

        Content subj = Content.builder().data(subject).build();
        Body body = Body.builder()
                .html(Content.builder().data(htmlBody == null ? "" : htmlBody).build())
                .text(Content.builder().data(textBody == null ? "" : textBody).build())
                .build();
        Message message = Message.builder().subject(subj).body(body).build();

        SendEmailRequest request = SendEmailRequest.builder()
                .destination(destination)
                .message(message)
                .source(fromAddress)
                .build();

        SendEmailResponse resp = sesClient.sendEmail(request);
        return resp.messageId();
    }

    /**
     * Send email to multiple recipients
     */
    public String sendEmailToMultiple(List<String> toAddresses, String subject, String htmlBody, String textBody) {
        Destination destination = Destination.builder().toAddresses(toAddresses).build();

        Content subj = Content.builder().data(subject).build();
        Body body = Body.builder()
                .html(Content.builder().data(htmlBody == null ? "" : htmlBody).build())
                .text(Content.builder().data(textBody == null ? "" : textBody).build())
                .build();
        Message message = Message.builder().subject(subj).body(body).build();

        SendEmailRequest request = SendEmailRequest.builder()
                .destination(destination)
                .message(message)
                .source(fromAddress)
                .build();

        SendEmailResponse resp = sesClient.sendEmail(request);
        return resp.messageId();
    }

    /**
     * Send templated email (future enhancement - SES templates)
     * For now, this is a placeholder for when SES email templates are implemented
     */
    public String sendTemplatedEmail(String toAddress, String templateName, java.util.Map<String, String> templateData) {
        // TODO: Implement SES email templates for more complex email formatting
        // This would use SendTemplatedEmailRequest
        throw new UnsupportedOperationException("Templated emails not yet implemented. Use sendEmail() instead.");
    }

    /**
     * Send payment confirmation email
     */
    public String sendPaymentConfirmation(String toEmail, String recipientName, String amount, String transactionId) {
        String subject = "Payment Confirmation - CareConnect";

        String htmlBody = String.format("""
                <!DOCTYPE html>
                <html>
                <head>
                    <style>
                        body { font-family: Arial, sans-serif; margin: 20px; }
                        .header { background-color: #4CAF50; color: white; padding: 10px; text-align: center; }
                        .content { margin: 20px 0; }
                        .footer { font-size: 12px; color: #666; margin-top: 30px; }
                    </style>
                </head>
                <body>
                    <div class="header">
                        <h1>CareConnect Payment Confirmation</h1>
                    </div>
                    <div class="content">
                        <p>Dear %s,</p>
                        <p>Thank you for your payment. We have successfully received your payment of <strong>$%s</strong>.</p>
                        <p><strong>Transaction ID:</strong> %s</p>
                        <p>If you have any questions about this transaction, please contact our support team.</p>
                        <p>Best regards,<br>The CareConnect Team</p>
                    </div>
                    <div class="footer">
                        <p>This is an automated message. Please do not reply to this email.</p>
                    </div>
                </body>
                </html>
                """, recipientName, amount, transactionId);

        String textBody = String.format(
                "Dear %s,\n\nThank you for your payment. We have successfully received your payment of $%s.\n\nTransaction ID: %s\n\nIf you have any questions, please contact support.\n\nBest regards,\nThe CareConnect Team",
                recipientName, amount, transactionId
        );

        return sendEmail(toEmail, subject, htmlBody, textBody);
    }

    /**
     * Send medication reminder email
     */
    public String sendMedicationReminder(String toEmail, String patientName, String medicationName, String dosage, String scheduledTime) {
        String subject = "Medication Reminder - " + medicationName;

        String htmlBody = String.format("""
                <!DOCTYPE html>
                <html>
                <head>
                    <style>
                        body { font-family: Arial, sans-serif; margin: 20px; }
                        .header { background-color: #FF9800; color: white; padding: 10px; text-align: center; }
                        .content { margin: 20px 0; }
                        .medication { background-color: #FFF3E0; padding: 15px; border-left: 4px solid #FF9800; margin: 10px 0; }
                        .footer { font-size: 12px; color: #666; margin-top: 30px; }
                    </style>
                </head>
                <body>
                    <div class="header">
                        <h1>Medication Reminder</h1>
                    </div>
                    <div class="content">
                        <p>Dear %s,</p>
                        <p>This is a reminder to take your medication.</p>
                        <div class="medication">
                            <h3>%s</h3>
                            <p><strong>Dosage:</strong> %s</p>
                            <p><strong>Scheduled Time:</strong> %s</p>
                        </div>
                        <p>Please take your medication as prescribed. If you have any questions, contact your healthcare provider.</p>
                        <p>Best regards,<br>The CareConnect Team</p>
                    </div>
                    <div class="footer">
                        <p>This is an automated reminder from CareConnect.</p>
                    </div>
                </body>
                </html>
                """, patientName, medicationName, dosage, scheduledTime);

        String textBody = String.format(
                "Dear %s,\n\nThis is a reminder to take your medication.\n\nMedication: %s\nDosage: %s\nScheduled Time: %s\n\nPlease take as prescribed.\n\nBest regards,\nThe CareConnect Team",
                patientName, medicationName, dosage, scheduledTime
        );

        return sendEmail(toEmail, subject, htmlBody, textBody);
    }

    /**
     * Send appointment reminder email
     */
    public String sendAppointmentReminder(String toEmail, String patientName, String appointmentType, String dateTime, String location) {
        String subject = buildAppointmentReminderSubject();
        String htmlBody = buildAppointmentReminderHtmlBody(dateTime);
        String textBody = buildAppointmentReminderTextBody(dateTime);

        return sendEmail(toEmail, subject, htmlBody, textBody);
    }

    public String buildAppointmentReminderSubject() {
        return "Appointment Reminder";
    }

    public String buildAppointmentReminderHtmlBody(String dateTime) {
        return String.format("""
                <!DOCTYPE html>
                <html>
                <head>
                    <style>
                        body { font-family: Arial, sans-serif; margin: 20px; }
                        .header { background-color: #2196F3; color: white; padding: 10px; text-align: center; }
                        .content { margin: 20px 0; }
                    </style>
                </head>
                <body>
                    <div class="header">
                        <h1>Appointment Reminder</h1>
                    </div>
                    <div class="content">
                        <p>You have a scheduled appointment for %s. If you have any questions, contact your provider.</p>
                    </div>
                </body>
                </html>
                """, dateTime);
    }

    public String buildAppointmentReminderTextBody(String dateTime) {
        return String.format(
                "You have a scheduled appointment for %s. If you have any questions, contact your provider.",
                dateTime
        );
    }

    /**
     * Send caregiver communication email
     */
    public String sendCaregiverMessage(String toEmail, String fromName, String toName, String message, String priority) {
        String subject = "Message from " + fromName + (priority.equals("urgent") ? " [URGENT]" : "");

        String htmlBody = String.format("""
                        <!DOCTYPE html>
                        <html>
                        <head>
                            <style>
                                body { font-family: Arial, sans-serif; margin: 20px; }
                                .header { background-color: %s; color: white; padding: 10px; text-align: center; }
                                .content { margin: 20px 0; }
                                .message { background-color: #F5F5F5; padding: 15px; border-left: 4px solid %s; margin: 10px 0; }
                                .footer { font-size: 12px; color: #666; margin-top: 30px; }
                            </style>
                        </head>
                        <body>
                            <div class="header">
                                <h1>New Message from %s</h1>
                            </div>
                            <div class="content">
                                <p>Dear %s,</p>
                                <p>You have received a new message in CareConnect.</p>
                                <div class="message">
                                    <p><strong>From:</strong> %s</p>
                                    <p><strong>Message:</strong></p>
                                    <p>%s</p>
                                </div>
                                <p>Please log in to CareConnect to respond or view additional details.</p>
                                <p>Best regards,<br>The CareConnect Team</p>
                            </div>
                            <div class="footer">
                                <p>This message was sent through CareConnect's secure communication system.</p>
                            </div>
                        </body>
                        </html>
                        """,
                priority.equals("urgent") ? "#F44336" : "#4CAF50",
                priority.equals("urgent") ? "#F44336" : "#4CAF50",
                fromName, toName, fromName, message.replace("\n", "<br>"));

        String textBody = String.format(
                "Dear %s,\n\nYou have received a new message from %s in CareConnect.\n\nMessage:\n%s\n\nPlease log in to respond.\n\nBest regards,\nThe CareConnect Team",
                toName, fromName, message
        );

        return sendEmail(toEmail, subject, htmlBody, textBody);
    }
}
