package com.careconnect.service;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

@Service
public class EmailTestService {

    @Value("${careconnect.email.provider:console}")
    private String emailProvider;

    @Value("${careconnect.email.from:noreply@careconnect.local}")
    private String fromEmail;

    @Value("${spring.mail.host:}")
    private String mailHost;

    @Value("${spring.mail.port:}")
    private String mailPort;

    @Value("${spring.mail.username:}")
    private String mailUsername;

    @Value("${careconnect.email.sendgrid.api-key:}")
    private String sendgridApiKey;

    @Value("${careconnect.email.resend.api-key:}")
    private String resendApiKey;

    @Value("${careconnect.email.mailgun.api-key:}")
    private String mailgunApiKey;

    @Value("${careconnect.email.mailgun.domain:}")
    private String mailgunDomain;

    @SuppressWarnings("SpringJavaInjectionPointsAutowiringInspection")
    @Autowired(required = false)
    private JavaMailSender mailSender;

    /**
     * Test email configuration and send a test email
     */
    public Map<String, Object> testEmailConfiguration(String testEmail) {
        Map<String, Object> result = new HashMap<>();
        result.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        result.put("testEmail", testEmail);
        result.put("emailProvider", emailProvider);
        result.put("fromEmail", fromEmail);

        // Check configuration
        Map<String, Object> config = getEmailConfiguration();
        result.put("configuration", config);

        // Test sending
        try {
            boolean success = sendTestEmail(testEmail);
            result.put("success", success);
            result.put("message", success ? "Test email sent successfully" : "Test email failed to send");
        } catch (Exception e) {
            result.put("success", false);
            result.put("message", "Test email failed: " + e.getMessage());
            result.put("error", e.getClass().getSimpleName());
        }

        return result;
    }

    /**
     * Get current email configuration details
     */
    public Map<String, Object> getEmailConfiguration() {
        Map<String, Object> config = new HashMap<>();
        config.put("provider", emailProvider);
        config.put("fromEmail", fromEmail);
        config.put("mailHost", mailHost);
        config.put("mailPort", mailPort);
        config.put("mailUsername", mailUsername);
        config.put("mailSenderAvailable", mailSender != null);

        // Check if configuration looks valid
        boolean hasValidConfig = false;
        if ("console".equals(emailProvider)) {
            hasValidConfig = true;
        } else if ("sendgrid".equals(emailProvider)) {
            hasValidConfig = sendgridApiKey != null && !sendgridApiKey.isEmpty();
        } else if ("resend".equals(emailProvider)) {
            hasValidConfig = resendApiKey != null && !resendApiKey.isEmpty();
        } else if ("mailgun".equals(emailProvider)) {
            hasValidConfig = mailgunApiKey != null && !mailgunApiKey.isEmpty() &&
                    mailgunDomain != null && !mailgunDomain.isEmpty();
        } else if (mailSender != null && !mailHost.isEmpty() && !mailPort.isEmpty()) {
            hasValidConfig = true;
        }
        config.put("configurationValid", hasValidConfig);

        // Add provider-specific configuration details
        switch (emailProvider.toLowerCase()) {
            case "sendgrid":
                config.put("sendgridConfigured", sendgridApiKey != null && !sendgridApiKey.isEmpty());
                break;
            case "resend":
                config.put("resendConfigured", resendApiKey != null && !resendApiKey.isEmpty());
                break;
            case "mailgun":
                config.put("mailgunConfigured", mailgunApiKey != null && !mailgunApiKey.isEmpty() &&
                        mailgunDomain != null && !mailgunDomain.isEmpty());
                break;
        }

        return config;
    }

    /**
     * Send a test email
     */
    public boolean sendTestEmail(String recipientEmail) throws MessagingException {
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        if ("console".equals(emailProvider) || mailSender == null) {
            // Console test mode disabled
            // System.out.println("🧪 EMAIL TEST - Console Mode:");
            // System.out.println("  Provider: " + emailProvider);
            // System.out.println("  To: " + recipientEmail);
            // System.out.println("  From: " + fromEmail);
            // System.out.println("  Subject: CareConnect Email Test");
            // System.out.println("  Timestamp: " + timestamp);
            // System.out.println("  Message: This is a test email from CareConnect backend");
            // System.out.println("  Configuration: Host=" + mailHost + ", Port=" + mailPort + ", Username=" + mailUsername);
            // System.out.println("  ===================================");
            return true;
        }

        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true);

            helper.setTo(recipientEmail);
            helper.setFrom(fromEmail);
            helper.setSubject("CareConnect Email Test - " + timestamp);
            helper.setText(buildTestEmailContent(timestamp), true);

            mailSender.send(message);
            // System.out.println("✅ Test email sent successfully via " + emailProvider + " to " + recipientEmail);
            return true;
        } catch (MessagingException e) {
            System.err.println("❌ Test email failed to send: " + e.getMessage());
            e.printStackTrace();
            throw e;
        }
    }

    /**
     * Build HTML content for test email
     */
    private String buildTestEmailContent(String timestamp) {
        return "<html><body>" +
                "<h2>CareConnect Email Test</h2>" +
                "<p><strong>Timestamp:</strong> " + timestamp + "</p>" +
                "<p><strong>Email Provider:</strong> " + emailProvider + "</p>" +
                "<p><strong>From:</strong> " + fromEmail + "</p>" +
                "<p><strong>Mail Host:</strong> " + mailHost + "</p>" +
                "<p><strong>Mail Port:</strong> " + mailPort + "</p>" +
                "<p><strong>Mail Username:</strong> " + mailUsername + "</p>" +
                "<hr>" +
                "<p>If you received this email, your CareConnect email configuration is working correctly!</p>" +
                "<p>This is a test email sent from the CareConnect backend system.</p>" +
                "<p><em>You can safely ignore this email.</em></p>" +
                "</body></html>";
    }

    /**
     * Validate email configuration without sending
     */
    public Map<String, Object> validateEmailConfiguration() {
        Map<String, Object> validation = new HashMap<>();
        validation.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));

        // Check provider setting
        boolean validProvider = emailProvider != null && !emailProvider.trim().isEmpty();
        validation.put("providerSet", validProvider);
        validation.put("provider", emailProvider);

        // Check from email
        boolean validFromEmail = fromEmail != null && !fromEmail.trim().isEmpty() && fromEmail.contains("@");
        validation.put("fromEmailValid", validFromEmail);
        validation.put("fromEmail", fromEmail);

        // Check mail sender
        boolean mailSenderExists = mailSender != null;
        validation.put("mailSenderExists", mailSenderExists);

        // Check SMTP configuration
        boolean smtpConfigValid = !mailHost.isEmpty() && !mailPort.isEmpty();
        validation.put("smtpConfigValid", smtpConfigValid);
        validation.put("mailHost", mailHost);
        validation.put("mailPort", mailPort);
        validation.put("mailUsername", mailUsername);

        // Overall validation
        boolean overallValid = validProvider && validFromEmail &&
                (emailProvider.equals("console") || (mailSenderExists && smtpConfigValid));
        validation.put("overallValid", overallValid);

        // Provide recommendations
        if (!overallValid) {
            validation.put("recommendations", getConfigurationRecommendations());
        }

        return validation;
    }

    /**
     * Get configuration recommendations
     */
    private String getConfigurationRecommendations() {
        StringBuilder recommendations = new StringBuilder();

        if (emailProvider == null || emailProvider.trim().isEmpty()) {
            recommendations.append("Set EMAIL_PROVIDER environment variable or careconnect.email.provider property. ");
        }

        if (fromEmail == null || fromEmail.trim().isEmpty() || !fromEmail.contains("@")) {
            recommendations.append("Set FROM_EMAIL environment variable or careconnect.email.from property with valid email. ");
        }

        if (mailSender == null && !"console".equals(emailProvider)) {
            recommendations.append("Configure JavaMailSender bean with SMTP settings. ");
        }

        if (mailHost.isEmpty() && !"console".equals(emailProvider)) {
            recommendations.append("Set MAIL_HOST environment variable or spring.mail.host property. ");
        }

        if (mailPort.isEmpty() && !"console".equals(emailProvider)) {
            recommendations.append("Set MAIL_PORT environment variable or spring.mail.port property. ");
        }

        return recommendations.toString();
    }

    /**
     * Send test emails for all authentication flows
     */
    public Map<String, Object> testAllEmailTypes(String testEmail) {
        Map<String, Object> results = new HashMap<>();
        results.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        results.put("testEmail", testEmail);

        // Test verification email
        try {
            boolean verificationSuccess = sendTestVerificationEmail(testEmail);
            results.put("verificationEmail", verificationSuccess ? "SUCCESS" : "FAILED");
        } catch (Exception e) {
            results.put("verificationEmail", "FAILED: " + e.getMessage());
        }

        // Test password reset email  
        try {
            boolean passwordResetSuccess = sendTestPasswordResetEmail(testEmail);
            results.put("passwordResetEmail", passwordResetSuccess ? "SUCCESS" : "FAILED");
        } catch (Exception e) {
            results.put("passwordResetEmail", "FAILED: " + e.getMessage());
        }

        // Test password setup email
        try {
            boolean passwordSetupSuccess = sendTestPasswordSetupEmail(testEmail);
            results.put("passwordSetupEmail", passwordSetupSuccess ? "SUCCESS" : "FAILED");
        } catch (Exception e) {
            results.put("passwordSetupEmail", "FAILED: " + e.getMessage());
        }

        return results;
    }

    private boolean sendTestVerificationEmail(String email) throws MessagingException {
        String testLink = "http://localhost:3000/verify?token=TEST_TOKEN_123";
        return sendTestEmailWithTemplate(email, "Email Verification Test",
                "This is a test of the email verification flow.", testLink, "VERIFY NOW");
    }

    private boolean sendTestPasswordResetEmail(String email) throws MessagingException {
        String testLink = "http://localhost:3000/reset?token=TEST_RESET_TOKEN_456";
        return sendTestEmailWithTemplate(email, "Password Reset Test",
                "This is a test of the password reset flow.", testLink, "RESET PASSWORD");
    }

    private boolean sendTestPasswordSetupEmail(String email) throws MessagingException {
        String testLink = "http://localhost:3000/setup?token=TEST_SETUP_TOKEN_789";
        return sendTestEmailWithTemplate(email, "Password Setup Test",
                "This is a test of the password setup flow.", testLink, "SET PASSWORD");
    }

    private boolean sendTestEmailWithTemplate(String email, String subject, String message,
                                              String link, String buttonText) throws MessagingException {
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        if ("console".equals(emailProvider) || mailSender == null) {
            // Console test logging disabled
            // System.out.println("🧪 EMAIL TEST - " + subject + ":");
            // System.out.println("  To: " + email);
            // System.out.println("  Subject: " + subject);
            // System.out.println("  Message: " + message);
            // System.out.println("  Link: " + link);
            // System.out.println("  Timestamp: " + timestamp);
            // System.out.println("  ===================================");
            return true;
        }

        try {
            MimeMessage mimeMessage = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(mimeMessage, true);

            helper.setTo(email);
            helper.setFrom(fromEmail);
            helper.setSubject(subject + " - " + timestamp);

            String htmlContent = "<html><body>" +
                    "<h2>" + subject + "</h2>" +
                    "<p>" + message + "</p>" +
                    "<p><a href=\"" + link + "\" style=\"background-color: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;\">" + buttonText + "</a></p>" +
                    "<p><em>This is a test email. Link: " + link + "</em></p>" +
                    "<p><small>Sent at: " + timestamp + "</small></p>" +
                    "</body></html>";

            helper.setText(htmlContent, true);
            mailSender.send(mimeMessage);
            // System.out.println("✅ Test " + subject + " sent successfully to " + email);
            return true;
        } catch (MessagingException e) {
            System.err.println("❌ Test " + subject + " failed: " + e.getMessage());
            throw e;
        }
    }

    /**
     * Send a simple test email and return result
     */
    public Map<String, Object> testSimpleEmail(String email) {
        Map<String, Object> result = new HashMap<>();
        result.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        result.put("recipientEmail", email);
        result.put("emailProvider", emailProvider);
        result.put("fromEmail", fromEmail);

        try {
            boolean success = sendTestEmail(email);
            result.put("success", success);
            result.put("message", success ? "Simple test email sent successfully" : "Simple test email failed to send");

        } catch (Exception e) {
            result.put("success", false);
            result.put("message", "Simple test email failed: " + e.getMessage());
            result.put("error", e.getClass().getSimpleName());
        }

        return result;
    }
}
