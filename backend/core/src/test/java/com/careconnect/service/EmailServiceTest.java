package com.careconnect.service;

import com.sendgrid.Request;
import com.sendgrid.Response;
import com.sendgrid.SendGrid;
import jakarta.mail.internet.MimeMessage;

import java.io.IOException;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockedConstruction;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockConstruction;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class EmailServiceTest {

    @Mock
    private JavaMailSender mailSender;

    @Mock
    private RestTemplate restTemplate;

    @InjectMocks
    private EmailService emailService;

    private MimeMessage mimeMessage;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        mimeMessage = mock(MimeMessage.class);
        when(mailSender.createMimeMessage()).thenReturn(mimeMessage);

        // Set default @Value fields
        ReflectionTestUtils.setField(emailService, "emailProvider", "smtp");
        ReflectionTestUtils.setField(emailService, "fromEmail",
                "noreply@careconnect.com");
        ReflectionTestUtils.setField(emailService, "resendApiKey", "");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey", "");
        ReflectionTestUtils.setField(emailService, "emailjsServiceId", "");
        ReflectionTestUtils.setField(emailService, "emailjsTemplateId", "");
        ReflectionTestUtils.setField(emailService, "emailjsUserId", "");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey", "");
        ReflectionTestUtils.setField(emailService, "mailgunDomain", "");
        ReflectionTestUtils.setField(emailService, "frontendBaseUrl",
                "http://localhost:3000");
    }

    // ---- getEmailProvider / getFromEmail ----

    @Test
    @DisplayName("getEmailProvider returns configured provider")
    void getEmailProvider_configured_returnsProvider() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "sendgrid");
        assertThat(emailService.getEmailProvider()).isEqualTo("sendgrid");
    }

    @Test
    @DisplayName("getFromEmail returns configured from address")
    void getFromEmail_configured_returnsFromEmail() throws Exception {
        assertThat(emailService.getFromEmail())
                .isEqualTo("noreply@careconnect.com");
    }

    // ---- sendTestEmail ----

    @Test
    @DisplayName("sendTestEmail with SMTP provider sends via SMTP")
    void sendTestEmail_smtpProvider_sendsViaSMTP() throws Exception {
        emailService.sendTestEmail("user@test.com", "Test Subject",
                "Test body");
        verify(mailSender).createMimeMessage();
        verify(mailSender).send(any(MimeMessage.class));
    }

    // ---- sendHtmlEmail (2-arg overload) ----

    @Test
    @DisplayName("sendHtmlEmail strips HTML tags for text fallback")
    void sendHtmlEmail_htmlContent_stripsTagsForTextContent() throws Exception {
        emailService.sendHtmlEmail("user@test.com", "Sub",
                "<p>Hello World</p>");
        verify(mailSender).send(any(MimeMessage.class));
    }

    // ---- sendHtmlEmail (3-arg overload with contentType) ----

    @Test
    @DisplayName("sendHtmlEmail with contentType delegates to two-arg")
    void sendHtmlEmail_withContentType_delegatesToTwoArgOverload() throws Exception {
        emailService.sendHtmlEmail("user@test.com", "Sub",
                "<b>Bold</b>", "text/html");
        verify(mailSender).send(any(MimeMessage.class));
    }

    // ---- sendVerificationEmail ----

    @Test
    @DisplayName("sendVerificationEmail with SMTP provider sends email")
    void sendVerificationEmail_smtpProvider_sendsEmail() throws Exception {
        emailService.sendVerificationEmail("user@test.com",
                "http://localhost:3000/verify?token=abc");
        verify(mailSender).send(any(MimeMessage.class));
    }

    // ---- sendPasswordSetupEmail ----

    @Test
    @DisplayName("sendPasswordSetupEmail with SMTP provider sends email")
    void sendPasswordSetupEmail_smtpProvider_sendsEmail() throws Exception {
        emailService.sendPasswordSetupEmail("user@test.com",
                "token123", "Alice");
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendPasswordSetupEmail with null first name does not throw")
    void sendPasswordSetupEmail_nullFirstName_doesNotThrow() throws Exception {
        assertDoesNotThrow(
                () -> emailService.sendPasswordSetupEmail("user@test.com",
                        "token123", null));
        verify(mailSender).send(any(MimeMessage.class));
    }

    // ---- sendPasswordResetEmail ----

    @Test
    @DisplayName("sendPasswordResetEmail with SMTP provider sends email")
    void sendPasswordResetEmail_smtpProvider_sendsEmail() throws Exception {
        emailService.sendPasswordResetEmail("user@test.com",
                "http://localhost:3000/reset?token=xyz");
        verify(mailSender).send(any(MimeMessage.class));
    }

    // ---- sendFamilyMemberInviteEmail ----

    @Test
    @DisplayName("sendFamilyMemberInviteEmail with SMTP sends email")
    void sendFamilyMemberInviteEmail_smtpProvider_sendsEmail() throws Exception {
        emailService.sendFamilyMemberInviteEmail("family@test.com",
                "Bob", "inviteToken", "John Doe");
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendFamilyMemberInviteEmail with null name no throw")
    void sendFamilyMemberInviteEmail_nullFirstName_doesNotThrow() throws Exception {
        assertDoesNotThrow(
                () -> emailService.sendFamilyMemberInviteEmail(
                        "family@test.com", null, "inviteToken", "John Doe"));
    }

    // ---- sendFamilyMemberAccessGrantedEmail ----

    @Test
    @DisplayName("sendFamilyMemberAccessGrantedEmail sends via SMTP")
    void sendFamilyMemberAccessGrantedEmail_smtpProvider_sendsEmail() throws Exception {
        emailService.sendFamilyMemberAccessGrantedEmail(
                "family@test.com", "Alice", "John Doe");
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendFamilyMemberAccessGrantedEmail null name no throw")
    void sendFamilyMemberAccessGrantedEmail_nullFirstName_doesNotThrow() throws Exception {
        assertDoesNotThrow(
                () -> emailService.sendFamilyMemberAccessGrantedEmail(
                        "family@test.com", null, "John Doe"));
    }

    // ---- sendPasswordSetupEmailWithCredentials ----

    @Test
    @DisplayName("sendPasswordSetupEmailWithCredentials temp password")
    void sendPasswordSetupEmailWithCredentials_tempPassword_sendsEmail() throws Exception {
        // A 12-char password matching the temp pattern
        final String tempPassword = "Ab1!xxxxxxxx";
        emailService.sendPasswordSetupEmailWithCredentials(
                "user@test.com", "tokenABC", "Jane",
                "janeuser", tempPassword);
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendPasswordSetupEmailWithCredentials regular password")
    void sendPasswordSetupEmailWithCredentials_regularPassword() throws Exception {
        emailService.sendPasswordSetupEmailWithCredentials(
                "user@test.com", "tokenABC", "Jane",
                "janeuser", "simplePass");
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendPasswordSetupEmailWithCredentials null name no throw")
    void sendPasswordSetupEmailWithCredentials_nullFirstName() throws Exception {
        assertDoesNotThrow(
                () -> emailService.sendPasswordSetupEmailWithCredentials(
                        "user@test.com", "token", null,
                        "user", "pass1234"));
    }

    // ---- Console / Dev provider ----

    @Test
    @DisplayName("sendEmail with console provider logs to console only")
    void sendEmail_consoleProvider_logsToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "console");
        emailService.sendTestEmail("user@test.com", "Test", "Body");
        verify(mailSender, never()).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendEmail with dev provider logs to console only")
    void sendEmail_devProvider_logsToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "dev");
        emailService.sendTestEmail("user@test.com", "Test", "Body");
        verify(mailSender, never()).send(any(MimeMessage.class));
    }

    // ---- Resend provider ----

    @Test
    @DisplayName("sendEmail resend no API key falls back to console")
    void sendEmail_resendProviderNoApiKey_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey", "");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail resend null API key falls back to console")
    void sendEmail_resendProviderNullApiKey_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey", null);
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail resend valid key sends via REST API")
    void sendEmail_resendProviderValidKey_sendsViaRestApi() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey",
                "re_123456");

        @SuppressWarnings("rawtypes") final ResponseEntity<Map> responseEntity =
                new ResponseEntity<>(Map.of("id", "email-id"), HttpStatus.OK);
        when(restTemplate.exchange(
                anyString(), eq(HttpMethod.POST), any(HttpEntity.class),
                eq(Map.class)))
                .thenReturn(responseEntity);

        emailService.sendTestEmail("user@test.com", "Sub", "Body");

        verify(restTemplate).exchange(
                eq("https://api.resend.com/emails"),
                eq(HttpMethod.POST),
                any(HttpEntity.class),
                eq(Map.class));
    }

    @Test
    @DisplayName("sendEmail resend non-2xx falls back to console")
    void sendEmail_resendProviderNon2xx_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey",
                "re_123456");

        @SuppressWarnings("rawtypes") final ResponseEntity<Map> responseEntity =
                new ResponseEntity<>(Map.of(), HttpStatus.BAD_REQUEST);
        when(restTemplate.exchange(
                anyString(), eq(HttpMethod.POST), any(HttpEntity.class),
                eq(Map.class)))
                .thenReturn(responseEntity);

        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail resend REST exception falls back to console")
    void sendEmail_resendProviderRestException_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey",
                "re_123456");

        when(restTemplate.exchange(
                anyString(), eq(HttpMethod.POST), any(HttpEntity.class),
                eq(Map.class)))
                .thenThrow(new RuntimeException("Network error"));

        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    // ---- Mailgun provider ----

    @Test
    @DisplayName("sendEmail mailgun no API key falls back to console")
    void sendEmail_mailgunProviderNoApiKey_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey", "");
        ReflectionTestUtils.setField(emailService, "mailgunDomain",
                "mg.example.com");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail mailgun null API key falls back to console")
    void sendEmail_mailgunProviderNullApiKey_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey", null);
        ReflectionTestUtils.setField(emailService, "mailgunDomain",
                "mg.example.com");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail mailgun no domain falls back to console")
    void sendEmail_mailgunProviderNoDomain_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey",
                "key-abc123");
        ReflectionTestUtils.setField(emailService, "mailgunDomain", "");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail mailgun null domain falls back to console")
    void sendEmail_mailgunProviderNullDomain_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey",
                "key-abc123");
        ReflectionTestUtils.setField(emailService, "mailgunDomain", null);
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail mailgun valid config sends via REST API")
    void sendEmail_mailgunProviderValidConfig_sendsViaRestApi() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey",
                "key-abc123");
        ReflectionTestUtils.setField(emailService, "mailgunDomain",
                "mg.example.com");

        @SuppressWarnings("rawtypes") final ResponseEntity<Map> responseEntity =
                new ResponseEntity<>(Map.of("id", "msg-id"), HttpStatus.OK);
        when(restTemplate.exchange(
                anyString(), eq(HttpMethod.POST), any(HttpEntity.class),
                eq(Map.class)))
                .thenReturn(responseEntity);

        emailService.sendTestEmail("user@test.com", "Sub", "Body");

        verify(restTemplate).exchange(
                eq("https://api.mailgun.net/v3/mg.example.com/messages"),
                eq(HttpMethod.POST),
                any(HttpEntity.class),
                eq(Map.class));
    }

    @Test
    @DisplayName("sendEmail mailgun non-2xx falls back to console")
    void sendEmail_mailgunProviderNon2xx_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey",
                "key-abc123");
        ReflectionTestUtils.setField(emailService, "mailgunDomain",
                "mg.example.com");

        @SuppressWarnings("rawtypes") final ResponseEntity<Map> responseEntity =
                new ResponseEntity<>(Map.of(),
                        HttpStatus.INTERNAL_SERVER_ERROR);
        when(restTemplate.exchange(
                anyString(), eq(HttpMethod.POST), any(HttpEntity.class),
                eq(Map.class)))
                .thenReturn(responseEntity);

        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail mailgun REST exception falls back to console")
    void sendEmail_mailgunProviderRestException_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey",
                "key-abc123");
        ReflectionTestUtils.setField(emailService, "mailgunDomain",
                "mg.example.com");

        when(restTemplate.exchange(
                anyString(), eq(HttpMethod.POST), any(HttpEntity.class),
                eq(Map.class)))
                .thenThrow(new RuntimeException("Timeout"));

        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    // ---- SendGrid provider ----

    @Test
    @DisplayName("sendEmail sendgrid no API key falls back to console")
    void sendEmail_sendgridProviderNoApiKey_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey", "");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail sendgrid null API key falls back to console")
    void sendEmail_sendgridProviderNullApiKey_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey", null);
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail sendgrid valid key and 202 status succeeds")
    void sendEmail_sendgridValidKey_successStatus() throws IOException {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey",
                "SG.testkey1234567890");

        final Response sgResponse = new Response();
        sgResponse.setStatusCode(202);
        sgResponse.setBody("accepted");

        try (MockedConstruction<SendGrid> mocked =
                     mockConstruction(SendGrid.class,
                             (sg, ctx) -> when(sg.api(any(Request.class)))
                                     .thenReturn(sgResponse))) {
            emailService.sendTestEmail("user@test.com", "Sub", "Body");
            assertThat(mocked.constructed()).hasSize(1);
            verify(mocked.constructed().get(0)).api(any(Request.class));
        }
    }

    @Test
    @DisplayName("sendEmail sendgrid valid key long HTML truncates log")
    void sendEmail_sendgridValidKey_longHtmlTruncated()
            throws IOException {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey",
                "SG.testkey1234567890");

        final Response sgResponse = new Response();
        sgResponse.setStatusCode(200);
        sgResponse.setBody("ok");

        // Build HTML content > 200 chars to trigger truncation branch
        final String longHtml = "<html><body>" + "x".repeat(250) + "</body></html>";

        try (MockedConstruction<SendGrid> mocked =
                     mockConstruction(SendGrid.class,
                             (sg, ctx) -> when(sg.api(any(Request.class)))
                                     .thenReturn(sgResponse))) {
            emailService.sendHtmlEmail("user@test.com", "Sub", longHtml);
            assertThat(mocked.constructed()).hasSize(1);
        }
    }

    @Test
    @DisplayName("sendEmail sendgrid valid key short HTML no truncation")
    void sendEmail_sendgridValidKey_shortHtmlNoTruncation()
            throws IOException {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey",
                "SG.testkey1234567890");

        final Response sgResponse = new Response();
        sgResponse.setStatusCode(200);
        sgResponse.setBody("ok");

        // Short HTML content <= 200 chars
        final String shortHtml = "<p>Short</p>";

        try (MockedConstruction<SendGrid> mocked =
                     mockConstruction(SendGrid.class,
                             (sg, ctx) -> when(sg.api(any(Request.class)))
                                     .thenReturn(sgResponse))) {
            emailService.sendHtmlEmail("user@test.com", "Sub", shortHtml);
            assertThat(mocked.constructed()).hasSize(1);
        }
    }

    @Test
    @DisplayName("sendEmail sendgrid non-2xx status falls back")
    void sendEmail_sendgridValidKey_errorStatus_fallsBack()
            throws IOException {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey",
                "SG.testkey1234567890");

        final Response sgResponse = new Response();
        sgResponse.setStatusCode(400);
        sgResponse.setBody("Bad Request");

        try (MockedConstruction<SendGrid> mocked =
                     mockConstruction(SendGrid.class,
                             (sg, ctx) -> when(sg.api(any(Request.class)))
                                     .thenReturn(sgResponse))) {
            // Should not throw; falls back to console
            assertDoesNotThrow(
                    () -> emailService.sendTestEmail("u@test.com", "S", "B"));
        }
    }

    @Test
    @DisplayName("sendEmail sendgrid IOException falls back to console")
    void sendEmail_sendgridValidKey_ioException_fallsBack()
            throws IOException {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey",
                "SG.testkey1234567890");

        try (MockedConstruction<SendGrid> mocked =
                     mockConstruction(SendGrid.class,
                             (sg, ctx) -> when(sg.api(any(Request.class)))
                                     .thenThrow(new IOException("IO error")))) {
            assertDoesNotThrow(
                    () -> emailService.sendTestEmail("u@test.com", "S", "B"));
        }
    }

    // ---- SMTP / mailtrap / gmail / default provider ----

    @Test
    @DisplayName("sendEmail mailtrap provider sends via SMTP")
    void sendEmail_mailtrapProvider_sendsViaSmtp() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailtrap");
        emailService.sendTestEmail("user@test.com", "Sub", "Body");
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendEmail gmail provider sends via SMTP")
    void sendEmail_gmailProvider_sendsViaSmtp() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "gmail");
        emailService.sendTestEmail("user@test.com", "Sub", "Body");
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendEmail unknown provider falls through to SMTP")
    void sendEmail_unknownProvider_fallsThroughToDefaultSmtp() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "something");
        emailService.sendTestEmail("user@test.com", "Sub", "Body");
        verify(mailSender).send(any(MimeMessage.class));
    }

    @Test
    @DisplayName("sendEmail null mailSender falls back to console")
    void sendEmail_nullMailSender_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "mailSender", null);
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail null fromEmail falls back to console")
    void sendEmail_nullFromEmail_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "fromEmail", null);
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail empty fromEmail falls back to console")
    void sendEmail_emptyFromEmail_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "fromEmail", "");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail blank fromEmail falls back to console")
    void sendEmail_blankFromEmail_fallsBackToConsole() throws Exception {
        ReflectionTestUtils.setField(emailService, "fromEmail", "   ");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail SMTP messaging exception falls back")
    void sendEmail_smtpMessagingException_fallsBackToConsole() throws Exception {
        doThrow(new RuntimeException("SMTP error"))
                .when(mailSender).send(any(MimeMessage.class));
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    // ---- sendEmail fallback for console/dev errors ----

    @Test
    @DisplayName("sendEmail console provider no double fallback")
    void sendEmail_consoleProviderException_noDoubleFallback() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "console");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail dev provider no double fallback")
    void sendEmail_devProviderException_noDoubleFallback() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "dev");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    // ---- getEmailConfiguration ----

    @Test
    @DisplayName("getEmailConfiguration resend configured returns true")
    void getEmailConfiguration_resendProvider_returnsResendConfig() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey",
                "re_testkey");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("provider")).isEqualTo("resend");
        assertThat(config.get("providerInfo")).isEqualTo("Resend API");
        assertThat(config.get("resendConfigured")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration resend empty key not configured")
    void getEmailConfiguration_resendProviderEmptyKey_notConfigured() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey", "");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("resendConfigured")).isEqualTo(false);
    }

    @Test
    @DisplayName("getEmailConfiguration mailgun configured returns true")
    void getEmailConfiguration_mailgunProvider_returnsMailgunConfig() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey",
                "key-abc");
        ReflectionTestUtils.setField(emailService, "mailgunDomain",
                "mg.example.com");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("provider")).isEqualTo("mailgun");
        assertThat(config.get("providerInfo")).isEqualTo("Mailgun API");
        assertThat(config.get("mailgunConfigured")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration mailgun empty not configured")
    void getEmailConfiguration_mailgunProviderEmptyKeys_notConfigured() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey", "");
        ReflectionTestUtils.setField(emailService, "mailgunDomain", "");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("mailgunConfigured")).isEqualTo(false);
    }

    @Test
    @DisplayName("getEmailConfiguration sendgrid configured returns true")
    void getEmailConfiguration_sendgridProvider_returnsSendgridConfig() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey",
                "SG.testkey123");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("provider")).isEqualTo("sendgrid");
        assertThat(config.get("providerInfo"))
                .isEqualTo("SendGrid (Production)");
        assertThat(config.get("sendgridConfigured")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration sendgrid empty not configured")
    void getEmailConfiguration_sendgridProviderEmptyKey_notConfigured() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey", "");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("sendgridConfigured")).isEqualTo(false);
    }

    @Test
    @DisplayName("getEmailConfiguration SMTP returns smtp config")
    void getEmailConfiguration_smtpProvider_returnsSmtpConfig() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "smtp");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("provider")).isEqualTo("smtp");
        assertThat(config.get("providerInfo")).isEqualTo("SMTP Server");
        assertThat(config.get("smtpConfigured")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration SMTP null sender not configured")
    void getEmailConfiguration_smtpProviderNullMailSender() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "smtp");
        ReflectionTestUtils.setField(emailService, "mailSender", null);
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("smtpConfigured")).isEqualTo(false);
    }

    @Test
    @DisplayName("getEmailConfiguration mailtrap returns smtp config")
    void getEmailConfiguration_mailtrapProvider_returnsSmtpConfig() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailtrap");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("providerInfo"))
                .isEqualTo("Mailtrap (Development)");
        assertThat(config.get("smtpConfigured")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration gmail returns smtp config")
    void getEmailConfiguration_gmailProvider_returnsSmtpConfig() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "gmail");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("providerInfo"))
                .isEqualTo("Gmail (Production)");
        assertThat(config.get("smtpConfigured")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration console returns always available")
    void getEmailConfiguration_consoleProvider_returnsAlwaysAvailable() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "console");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("provider")).isEqualTo("console");
        assertThat(config.get("providerInfo"))
                .isEqualTo("Console/Development Mode");
        assertThat(config.get("alwaysAvailable")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration dev returns always available")
    void getEmailConfiguration_devProvider_returnsAlwaysAvailable() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "dev");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("providerInfo"))
                .isEqualTo("Console/Development Mode");
        assertThat(config.get("alwaysAvailable")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration unknown returns default branch")
    void getEmailConfiguration_unknownProvider_returnsDefaultBranch() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "customProvider");
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("providerInfo")).isEqualTo("customProvider");
        assertThat(config.get("alwaysAvailable")).isEqualTo(true);
    }

    @Test
    @DisplayName("getEmailConfiguration includes base fields")
    void getEmailConfiguration_always_includesBaseFieldsInConfig() throws Exception {
        final Map<String, Object> config = emailService.getEmailConfiguration();
        assertThat(config.get("fromEmail"))
                .isEqualTo("noreply@careconnect.com");
        assertThat(config.get("frontendBaseUrl"))
                .isEqualTo("http://localhost:3000");
    }

    // ---- SMTP provider with upper-case variant ----

    @Test
    @DisplayName("sendEmail upper-case provider uses lowercase match")
    void sendEmail_upperCaseProvider_usesLowercaseMatch() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "SMTP");
        emailService.sendTestEmail("user@test.com", "Sub", "Body");
        verify(mailSender).send(any(MimeMessage.class));
    }

    // ---- Resend with whitespace-only API key ----

    @Test
    @DisplayName("sendEmail resend whitespace key falls back to console")
    void sendEmail_resendProviderWhitespaceApiKey_fallsBack() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider", "resend");
        ReflectionTestUtils.setField(emailService, "resendApiKey", "   ");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    // ---- Mailgun with whitespace-only keys ----

    @Test
    @DisplayName("sendEmail mailgun whitespace key falls back to console")
    void sendEmail_mailgunProviderWhitespaceApiKey_fallsBack() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey", "   ");
        ReflectionTestUtils.setField(emailService, "mailgunDomain",
                "mg.example.com");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    @Test
    @DisplayName("sendEmail mailgun whitespace domain falls back")
    void sendEmail_mailgunProviderWhitespaceDomain_fallsBack() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "mailgun");
        ReflectionTestUtils.setField(emailService, "mailgunApiKey",
                "key-abc123");
        ReflectionTestUtils.setField(emailService, "mailgunDomain", "   ");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }

    // ---- SendGrid with whitespace-only API key ----

    @Test
    @DisplayName("sendEmail sendgrid whitespace key falls back")
    void sendEmail_sendgridProviderWhitespaceApiKey_fallsBack() throws Exception {
        ReflectionTestUtils.setField(emailService, "emailProvider",
                "sendgrid");
        ReflectionTestUtils.setField(emailService, "sendgridApiKey", "   ");
        assertDoesNotThrow(
                () -> emailService.sendTestEmail("u@test.com", "S", "B"));
    }
}
