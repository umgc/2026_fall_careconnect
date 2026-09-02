package com.careconnect.service;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

// SendGrid imports
import com.sendgrid.*;
import com.sendgrid.Method;
import com.sendgrid.Request;
import com.sendgrid.Response;
import com.sendgrid.SendGrid;
import com.sendgrid.helpers.mail.Mail;
import com.sendgrid.helpers.mail.objects.Email;
import com.sendgrid.helpers.mail.objects.Content;

import java.io.IOException;

import java.util.HashMap;
import java.util.Map;

@Service
public class EmailService {

    @Value("${careconnect.email.provider:mailtrap}")
    private String emailProvider;

    @Value("${careconnect.email.from:noreply@careconnect.com}")
    private String fromEmail;

    // API-based email service configurations
    @Value("${careconnect.email.resend.api-key:}")
    private String resendApiKey;

    @Value("${careconnect.email.sendgrid.api-key:}")
    private String sendgridApiKey;

    @Value("${careconnect.email.emailjs.service-id:}")
    private String emailjsServiceId;

    @Value("${careconnect.email.emailjs.template-id:}")
    private String emailjsTemplateId;

    @Value("${careconnect.email.emailjs.user-id:}")
    private String emailjsUserId;

    @Value("${careconnect.email.mailgun.api-key:}")
    private String mailgunApiKey;

    @Value("${careconnect.email.mailgun.domain:}")
    private String mailgunDomain;

    @Value("${frontend.base-url:http://localhost:3000}")
    private String frontendBaseUrl;

    @SuppressWarnings("SpringJavaInjectionPointsAutowiringInspection")
    @Autowired(required = false)
    private JavaMailSender mailSender;

    @Autowired
    private RestTemplate restTemplate;

    /**
     * Send password setup email with backend-generated credentials
     */
    public void sendPasswordSetupEmailWithCredentials(String recipientEmail, String passwordSetupToken, String firstName, String username, String password) {
        String setupLink = frontendBaseUrl + "/setup-password?token=" + passwordSetupToken;
        String subject = "Welcome to CareConnect - Complete Your Registration";

        boolean isTemporaryPassword = password.length() == 12 && password.matches(".*[A-Z].*[a-z].*[0-9].*[!@#$%^&*()_+\\-=].*");
        String htmlContent = buildWelcomeEmailHtml(firstName, setupLink, username, password, isTemporaryPassword);

        String textContent = "Hello " + (firstName != null ? firstName : "") + ",\n\n" +
                "Your CareConnect account has been created.\n" +
                "Username: " + username + "\n" +
                (isTemporaryPassword ? "Temporary Password: " : "Password: ") + password + "\n\n" +
                "Please complete your registration by clicking this link: " + setupLink + "\n\n" +
                (isTemporaryPassword ? "For security, please change your password after logging in." : "");

        sendEmail(recipientEmail, subject, htmlContent, textContent);
    }

    /**
     * HTML template for password setup email with credentials
     */
    private String buildWelcomeEmailHtml(String firstName, String setupLink, String username, String password, boolean isTemporary) {
        return "<html><body style='font-family: Arial, sans-serif; line-height: 1.6; color: #333;'>" +
                "<div style='max-width: 600px; margin: 0 auto; padding: 20px;'>" +
                "<h2 style='color: #007bff;'>Welcome to CareConnect!</h2>" +
                "<p>Hello " + (firstName != null ? firstName : "") + ",</p>" +
                "<p>Your CareConnect account has been created. Here are your login credentials:</p>" +
                "<div style='background: #f8f9fa; border-radius: 5px; padding: 15px; margin: 20px 0;'>" +
                "<strong>Username (Email):</strong> " + username + "<br>" +
                "<strong>" + (isTemporary ? "Temporary Password" : "Password") + ":</strong> " +
                "<span style='font-family: monospace;'>" + password + "</span>" +
                "</div>" +
                "<p><strong>Next Steps:</strong></p>" +
                "<ol>" +
                "<li>Click the button below to complete your registration</li>" +
                (isTemporary ? "<li>After registering, please change your temporary password</li>" : "") +
                "</ol>" +
                "<div style='text-align: center; margin: 30px 0;'>" +
                "<a href='" + setupLink + "' style='background-color: #007bff; color: white; padding: 12px 24px; " +
                "text-decoration: none; border-radius: 5px;'>Complete Registration</a>" +
                "</div>" +
                "</div>" +
                "<p style='margin-top: 30px; font-size: 14px; color: #666;'>If you did not expect this email, please contact your caregiver.</p>" +
                "</div></body></html>";
    }

    public void sendVerificationEmail(String recipientEmail, String verificationLink) {
        String subject = "CareConnect Email Verification";
        String htmlContent = buildVerificationEmailHtml(verificationLink);
        String textContent = "Please verify your email by clicking: " + verificationLink;

        sendEmail(recipientEmail, subject, htmlContent, textContent);
    }

    public void sendPasswordSetupEmail(String recipientEmail, String passwordSetupToken, String firstName) {
        String passwordSetupLink = frontendBaseUrl + "/setup-password?token=" + passwordSetupToken;
        String subject = "CareConnect - Set Up Your Password";
        String htmlContent = buildPasswordSetupEmailHtml(firstName, passwordSetupLink);
        String textContent = "Set up your password by clicking: " + passwordSetupLink;

        sendEmail(recipientEmail, subject, htmlContent, textContent);
    }

    public void sendPasswordResetEmail(String recipientEmail, String resetLink) {
        String subject = "CareConnect Password Reset";
        String htmlContent = buildPasswordResetEmailHtml(resetLink);
        String textContent = "Reset your password by clicking: " + resetLink;

        sendEmail(recipientEmail, subject, htmlContent, textContent);
    }

    public void sendFamilyMemberInviteEmail(String recipientEmail, String firstName, String passwordSetupToken, String patientName) {
        String passwordSetupLink = frontendBaseUrl + "/setup-password?token=" + passwordSetupToken;
        String subject = "CareConnect - Family Member Invitation";
        String htmlContent = buildFamilyMemberInviteEmailHtml(firstName, passwordSetupLink, patientName);
        String textContent = "You've been invited to CareConnect. Set up your password: " + passwordSetupLink;

        sendEmail(recipientEmail, subject, htmlContent, textContent);
    }

    public void sendFamilyMemberAccessGrantedEmail(String recipientEmail, String firstName, String patientName) {
        String loginLink = frontendBaseUrl + "/login";
        String subject = "CareConnect - New Patient Access Granted";
        String htmlContent = buildFamilyMemberAccessGrantedEmailHtml(firstName, patientName, loginLink);
        String textContent = "Hello " + (firstName != null ? firstName : "") + ",\n\n" +
                "You have been granted access to a new patient in CareConnect: " + patientName + ".\n\n" +
                "You can now log in to view their information: " + loginLink + "\n\n" +
                "Best regards,\nThe CareConnect Team";

        sendEmail(recipientEmail, subject, htmlContent, textContent);
    }

    /**
     * HTML template for family member access granted email
     */
    private String buildFamilyMemberAccessGrantedEmailHtml(String firstName, String patientName, String loginLink) {
        return "<html><body style='font-family: Arial, sans-serif; line-height: 1.6; color: #333;'>" +
                "<div style='max-width: 600px; margin: 0 auto; padding: 20px;'>" +
                "<h2 style='color: #007bff;'>New Patient Access Granted</h2>" +
                "<p>Hello " + (firstName != null ? firstName : "") + ",</p>" +
                "<p>You have been granted access to a new patient in CareConnect:</p>" +
                "<div style='background: #f8f9fa; border-radius: 5px; padding: 15px; margin: 20px 0;'>" +
                "<strong>Patient:</strong> " + patientName +
                "</div>" +
                "<p>You can now log in to view their information and assist with their care.</p>" +
                "<div style='text-align: center; margin: 30px 0;'>" +
                "<a href='" + loginLink + "' style='background-color: #007bff; color: white; padding: 12px 24px; " +
                "text-decoration: none; border-radius: 5px;'>Log In to CareConnect</a>" +
                "</div>" +
                "<p style='margin-top: 30px; font-size: 14px; color: #666;'>If you did not expect this access, please contact the patient or their caregiver.</p>" +
                "</div></body></html>";
    }

    /**
     * Core email sending method that routes to appropriate provider
     */
    private void sendEmail(String recipientEmail, String subject, String htmlContent, String textContent) {
        try {
            switch (emailProvider.toLowerCase()) {
                case "console":
                case "dev":
                    sendConsoleEmail(recipientEmail, subject, textContent);
                    break;
                case "resend":
                    sendResendEmail(recipientEmail, subject, htmlContent);
                    break;
                case "sendgrid":
                    sendSendgridEmail(recipientEmail, subject, htmlContent);
                    break;
                case "mailgun":
                    sendMailgunEmail(recipientEmail, subject, htmlContent);
                    break;
                case "smtp":
                case "mailtrap":
                case "gmail":
                default:
                    sendSmtpEmail(recipientEmail, subject, htmlContent);
                    break;
            }
        } catch (Exception e) {
            System.err.println("❌ Failed to send email via " + emailProvider + ": " + e.getMessage());
            e.printStackTrace();

            // Fallback to console mode if email sending fails
            // BUT NOT for console or dev modes (they don't "fail")
            if (!"console".equals(emailProvider) && !"dev".equals(emailProvider)) {
                // System.out.println("🔄 Falling back to console mode...");
                sendConsoleEmail(recipientEmail, subject, textContent);
            }
        }
    }

    /**
     * Console/Development mode - log email to console
     */
    private void sendConsoleEmail(final String recipientEmail, final String subject, final String content) {
        System.out.println("🔧 DEV MODE - Email logged to console:");
        System.out.println("  Provider: " + emailProvider);
        System.out.println("  To: " + recipientEmail);
        System.out.println("  From: " + fromEmail);
        System.out.println("  Subject: " + subject);
        System.out.println("  Content: " + content);
        System.out.println("  ===================================");
    }

    /**
     * Resend API - Simple API-based email service
     */
    private void sendResendEmail(String recipientEmail, String subject, String htmlContent) {
        if (resendApiKey == null || resendApiKey.trim().isEmpty()) {
            throw new RuntimeException("Resend API key not configured. Set RESEND_API_KEY environment variable.");
        }

        try {
            String url = "https://api.resend.com/emails";

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(resendApiKey);

            Map<String, Object> emailData = new HashMap<>();
            emailData.put("from", fromEmail);
            emailData.put("to", new String[]{recipientEmail});
            emailData.put("subject", subject);
            emailData.put("html", htmlContent);

            HttpEntity<Map<String, Object>> request = new HttpEntity<>(emailData, headers);
            ResponseEntity<Map> response = restTemplate.exchange(url, HttpMethod.POST, request, Map.class);

            if (response.getStatusCode().is2xxSuccessful()) {
                // System.out.println("✅ Email sent via Resend to " + recipientEmail);
            } else {
                throw new RuntimeException("Resend API returned status: " + response.getStatusCode());
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to send email via Resend: " + e.getMessage(), e);
        }
    }

    /**
     * Mailgun API - Simple API-based email service
     */
    private void sendMailgunEmail(String recipientEmail, String subject, String htmlContent) {
        if (mailgunApiKey == null || mailgunApiKey.trim().isEmpty() ||
                mailgunDomain == null || mailgunDomain.trim().isEmpty()) {
            throw new RuntimeException("Mailgun configuration incomplete. Set MAILGUN_API_KEY and MAILGUN_DOMAIN environment variables.");
        }

        try {
            String url = "https://api.mailgun.net/v3/" + mailgunDomain + "/messages";

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
            headers.setBasicAuth("api", mailgunApiKey);

            String body = "from=" + fromEmail +
                    "&to=" + recipientEmail +
                    "&subject=" + subject +
                    "&html=" + htmlContent;

            HttpEntity<String> request = new HttpEntity<>(body, headers);
            ResponseEntity<Map> response = restTemplate.exchange(url, HttpMethod.POST, request, Map.class);

            if (response.getStatusCode().is2xxSuccessful()) {
                // System.out.println("✅ Email sent via Mailgun to " + recipientEmail);
            } else {
                throw new RuntimeException("Mailgun API returned status: " + response.getStatusCode());
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to send email via Mailgun: " + e.getMessage(), e);
        }
    }

    /**
     * SendGrid API - Production-grade email service
     */
    private void sendSendgridEmail(String recipientEmail, String subject, String htmlContent) {
        if (sendgridApiKey == null || sendgridApiKey.trim().isEmpty()) {
            throw new RuntimeException("SendGrid API key not configured. Set SENDGRID_API_KEY environment variable.");
        }

        try {
            Email from = new Email(fromEmail, "CareConnect");
            Email to = new Email(recipientEmail);
            Content content = new Content("text/html", htmlContent);
            Mail mail = new Mail(from, subject, to, content);

            SendGrid sg = new SendGrid(sendgridApiKey);
            Request request = new Request();
            request.setMethod(Method.POST);
            request.setEndpoint("mail/send");
            request.setBody(mail.build());

            // Print outgoing request details for debugging
            System.out.println("\n==== SENDGRID OUTGOING REQUEST ====");
            System.out.println("API KEY: " + (sendgridApiKey != null ? sendgridApiKey.substring(0, 8) + "..." : "null"));
            System.out.println("From: " + fromEmail);
            System.out.println("To: " + recipientEmail);
            System.out.println("Subject: " + subject);
            System.out.println("Body (truncated): " + htmlContent.substring(0, Math.min(200, htmlContent.length())) + (htmlContent.length() > 200 ? "..." : ""));
            System.out.println("Raw JSON Payload: " + mail.build());
            System.out.println("==== END SENDGRID REQUEST ====");

            Response response = sg.api(request);
            System.out.println("SendGrid Response: Status=" + response.getStatusCode() + ", Body=" + response.getBody());
            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                // Email sent successfully
            } else {
                throw new RuntimeException("SendGrid API returned status: " + response.getStatusCode() + " - " + response.getBody());
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to send email via SendGrid: " + e.getMessage(), e);
        }
    }

    /**
     * SMTP-based email sending (production mode)
     */
    private void sendSmtpEmail(String recipientEmail, String subject, String htmlContent) {
        // If using SendGrid SMTP, set username="apikey" and password=actual API key in properties
        if (mailSender == null) {
            throw new RuntimeException("SMTP configuration not available. Configure JavaMailSender or use a different email provider.");
        }
        if (fromEmail == null || fromEmail.trim().isEmpty()) {
            System.err.println("❌ ERROR: fromEmail is null or empty! Check your environment variables and application.properties mapping.");
            throw new RuntimeException("FROM_EMAIL (careconnect.email.from) is not set. Email cannot be sent.");
        }
        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true);
            helper.setTo(recipientEmail);
            System.out.println("DEBUG: Sending SMTP email with FROM: '" + fromEmail + "'");
            helper.setFrom(fromEmail);
            helper.setSubject(subject);
            helper.setText(htmlContent, true);
            mailSender.send(message);
        } catch (MessagingException e) {
            System.err.println("❌ SMTP Email failed. FROM_EMAIL: '" + fromEmail + "'");
            throw new RuntimeException("Failed to send SMTP email: " + e.getMessage(), e);
        }
    }

    /**
     * Get human-readable provider information
     */
    private String getProviderInfo() {
        switch (emailProvider.toLowerCase()) {
            case "console":
            case "dev":
                return "Console/Development Mode";
            case "resend":
                return "Resend API";
            case "mailgun":
                return "Mailgun API";
            case "sendgrid":
                return "SendGrid (Production)";
            case "mailtrap":
                return "Mailtrap (Development)";
            case "gmail":
                return "Gmail (Production)";
            case "smtp":
                return "SMTP Server";
            default:
                return emailProvider;
        }
    }

    /**
     * Get current email provider
     */
    public String getEmailProvider() {
        return emailProvider;
    }

    /**
     * Get current FROM_EMAIL
     */
    public String getFromEmail() {
        return fromEmail;
    }

    /**
     * Send a test email (for testing purposes)
     */
    public void sendTestEmail(String recipientEmail, String subject, String content) {
        sendEmail(recipientEmail, subject, content, content);
    }

    public void sendHtmlEmail(String recipientEmail, String subject, String htmlContent) {
        // Use the same HTML content as text content for the fallback
        // This isn't ideal for accessibility, but works as a simple solution
        String textContent = htmlContent.replaceAll("<[^>]*>", "")
                .replaceAll("\\s+", " ")
                .trim();

        sendEmail(recipientEmail, subject, htmlContent, textContent);
    }

    // Overload for backward compatibility with code that includes content type
    public void sendHtmlEmail(String recipientEmail, String subject, String htmlContent, String contentType) {
        // Ignore the contentType parameter as we're always sending HTML
        sendHtmlEmail(recipientEmail, subject, htmlContent);
    }

    /**
     * HTML email templates
     */
    private String buildVerificationEmailHtml(String verificationLink) {
        return "<html><body style='font-family: Arial, sans-serif; line-height: 1.6; color: #333;'>" +
                "<div style='max-width: 600px; margin: 0 auto; padding: 20px;'>" +
                "<h2 style='color: #007bff;'>Welcome to CareConnect!</h2>" +
                "<p>Thank you for registering with CareConnect.</p>" +
                "<p>Please click the button below to verify your email address:</p>" +
                "<p style='text-align: center; margin: 30px 0;'>" +
                "<a href=\"" + verificationLink + "\" style='background-color: #007bff; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; display: inline-block;'>VERIFY EMAIL</a>" +
                "</p>" +
                "<p>If the button doesn't work, copy and paste this link into your browser:</p>" +
                "<p style='word-break: break-all; color: #666;'>" + verificationLink + "</p>" +
                "<p style='margin-top: 30px; font-size: 14px; color: #666;'>If you did not create an account, you can safely ignore this email.</p>" +
                "</div></body></html>";
    }

    private String buildPasswordSetupEmailHtml(String firstName, String passwordSetupLink) {
        return "<html><body style='font-family: Arial, sans-serif; line-height: 1.6; color: #333;'>" +
                "<div style='max-width: 600px; margin: 0 auto; padding: 20px;'>" +
                "<h2 style='color: #007bff;'>Set Up Your CareConnect Password</h2>" +
                "<p>Hello " + (firstName != null ? firstName : "") + ",</p>" +
                "<p>A caregiver has created an account for you on CareConnect.</p>" +
                "<p>To complete your account setup, please click the button below to create your password:</p>" +
                "<p style='text-align: center; margin: 30px 0;'>" +
                "<a href=\"" + passwordSetupLink + "\" style='background-color: #28a745; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; display: inline-block;'>SET UP PASSWORD</a>" +
                "</p>" +
                "<p>If the button doesn't work, copy and paste this link into your browser:</p>" +
                "<p style='word-break: break-all; color: #666;'>" + passwordSetupLink + "</p>" +
                "<p style='color: #dc3545; font-weight: bold;'>This link will expire in 24 hours for security reasons.</p>" +
                "<p style='margin-top: 30px; font-size: 14px; color: #666;'>If you did not expect this email, please contact your caregiver.</p>" +
                "</div></body></html>";
    }

    private String buildPasswordResetEmailHtml(String resetLink) {
        return "<html><body style='font-family: Arial, sans-serif; line-height: 1.6; color: #333;'>" +
                "<div style='max-width: 600px; margin: 0 auto; padding: 20px;'>" +
                "<h2 style='color: #007bff;'>Reset Your CareConnect Password</h2>" +
                "<p>You requested a password reset for your CareConnect account.</p>" +
                "<p>Click the button below to reset your password:</p>" +
                "<p style='text-align: center; margin: 30px 0;'>" +
                "<a href=\"" + resetLink + "\" style='background-color: #dc3545; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; display: inline-block;'>RESET PASSWORD</a>" +
                "</p>" +
                "<p>If the button doesn't work, copy and paste this link into your browser:</p>" +
                "<p style='word-break: break-all; color: #666;'>" + resetLink + "</p>" +
                "<p style='color: #dc3545; font-weight: bold;'>This link will expire in 2 hours for security reasons.</p>" +
                "<p style='margin-top: 30px; font-size: 14px; color: #666;'>If you did not request this password reset, you can safely ignore this email.</p>" +
                "</div></body></html>";
    }

    private String buildFamilyMemberInviteEmailHtml(String firstName, String passwordSetupLink, String patientName) {
        return "<html><body style='font-family: Arial, sans-serif; line-height: 1.6; color: #333;'>" +
                "<div style='max-width: 600px; margin: 0 auto; padding: 20px;'>" +
                "<h2 style='color: #007bff;'>You're Invited to CareConnect!</h2>" +
                "<p>Hello " + (firstName != null ? firstName : "") + ",</p>" +
                "<p>You have been invited to join CareConnect as a family member to access <strong>" + patientName + "'s</strong> health information.</p>" +
                "<p>To complete your account setup, please click the button below to create your password:</p>" +
                "<p style='text-align: center; margin: 30px 0;'>" +
                "<a href=\"" + passwordSetupLink + "\" style='background-color: #17a2b8; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; display: inline-block;'>SET UP PASSWORD</a>" +
                "</p>" +
                "<p>If the button doesn't work, copy and paste this link into your browser:</p>" +
                "<p style='word-break: break-all; color: #666;'>" + passwordSetupLink + "</p>" +
                "<div style='background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;'>" +
                "<p style='margin: 0; font-weight: bold;'>Once you set up your password, you'll be able to:</p>" +
                "<ul style='margin: 10px 0;'>" +
                "<li>View patient health information</li>" +
                "<li>Access vital signs and health metrics</li>" +
                "<li>See health analytics and reports</li>" +
                "</ul>" +
                "<p style='margin: 0; font-style: italic; color: #666;'>Note: Your access is read-only for privacy and security.</p>" +
                "</div>" +
                "<p style='color: #dc3545; font-weight: bold;'>This link will expire in 24 hours for security reasons.</p>" +
                "<p style='margin-top: 30px; font-size: 14px; color: #666;'>If you did not expect this email, please contact the patient or caregiver who invited you.</p>" +
                "</div></body></html>";
    }

    /**
     * Test email configuration and capabilities
     */
    public Map<String, Object> getEmailConfiguration() {
        Map<String, Object> config = new HashMap<>();
        config.put("provider", emailProvider);
        config.put("providerInfo", getProviderInfo());
        config.put("fromEmail", fromEmail);
        config.put("frontendBaseUrl", frontendBaseUrl);

        // Check provider-specific configuration
        switch (emailProvider.toLowerCase()) {
            case "resend":
                config.put("resendConfigured", !resendApiKey.isEmpty());
                break;
            case "mailgun":
                config.put("mailgunConfigured", !mailgunApiKey.isEmpty() && !mailgunDomain.isEmpty());
                break;
            case "sendgrid":
                config.put("sendgridConfigured", !sendgridApiKey.isEmpty());
                break;
            case "smtp":
            case "mailtrap":
            case "gmail":
                config.put("smtpConfigured", mailSender != null);
                break;
            case "console":
            case "dev":
            default:
                config.put("alwaysAvailable", true);
                break;
        }

        return config;
    }
}
