package com.careconnect.controller;

import com.careconnect.service.EmailTestService;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EmailTestControllerTest {

    private static final String TEST_EMAIL = "test@example.com";
    @Mock
    private EmailTestService emailTestService;

    // ── shared constants ──────────────────────────────────────────────────────
    @InjectMocks
    private EmailTestController controller;

    // ── shared helpers ────────────────────────────────────────────────────────

    /**
     * Returns a mutable config map so individual tests can override fields.
     */
    private Map<String, Object> configMap(boolean valid) {
        final Map<String, Object> config = new HashMap<>();
        config.put("configurationValid", valid);
        config.put("provider", "console");
        config.put("mailSenderAvailable", true);
        return config;
    }

    // ── POST /v1/api/email-test/send ──────────────────────────────────────────

    @Nested
    class SendTestEmail {

        @Test
        void returns200_whenEmailIsValid() throws Exception {
            when(emailTestService.testEmailConfiguration(TEST_EMAIL)).thenReturn(Map.of("success", true));

            final ResponseEntity<Map<String, Object>> response =
                    controller.sendTestEmail(Map.of("email", TEST_EMAIL));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult_whenEmailIsValid() throws Exception {
            final Map<String, Object> serviceResult = Map.of("success", true, "message", "sent");
            when(emailTestService.testEmailConfiguration(TEST_EMAIL)).thenReturn(serviceResult);

            final ResponseEntity<Map<String, Object>> response =
                    controller.sendTestEmail(Map.of("email", TEST_EMAIL));

            assertThat(response.getBody()).isEqualTo(serviceResult);
        }

        @Test
        void callsServiceWithCorrectEmail() throws Exception {
            when(emailTestService.testEmailConfiguration(TEST_EMAIL)).thenReturn(Map.of());

            controller.sendTestEmail(Map.of("email", TEST_EMAIL));

            verify(emailTestService).testEmailConfiguration(TEST_EMAIL);
        }

        @Test
        void returns400_whenEmailKeyAbsent() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.sendTestEmail(Collections.emptyMap());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void returns400_whenEmailIsNull() throws Exception {
            final Map<String, String> body = new HashMap<>();
            body.put("email", null);

            final ResponseEntity<Map<String, Object>> response = controller.sendTestEmail(body);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void returns400_whenEmailIsEmpty() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.sendTestEmail(Map.of("email", ""));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void returns400_whenEmailIsBlankWhitespace() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.sendTestEmail(Map.of("email", "   "));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void errorBodyContainsRequiredMessage_whenEmailMissing() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.sendTestEmail(Collections.emptyMap());

            assertThat(response.getBody())
                    .containsEntry("error", "Email address is required");
        }

        @Test
        void doesNotCallService_whenEmailIsNull() throws Exception {
            final Map<String, String> body = new HashMap<>();
            body.put("email", null);

            controller.sendTestEmail(body);

            verifyNoInteractions(emailTestService);
        }

        @Test
        void doesNotCallService_whenEmailIsEmpty() throws Exception {
            controller.sendTestEmail(Map.of("email", ""));

            verifyNoInteractions(emailTestService);
        }

        @Test
        void doesNotCallService_whenEmailIsBlank() throws Exception {
            controller.sendTestEmail(Map.of("email", "   "));

            verifyNoInteractions(emailTestService);
        }
    }

    // ── GET /v1/api/email-test/config ─────────────────────────────────────────

    @Nested
    class GetEmailConfig {

        @Test
        void returns200() throws Exception {
            when(emailTestService.getEmailConfiguration()).thenReturn(Map.of());

            final ResponseEntity<Map<String, Object>> response = controller.getEmailConfig();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final Map<String, Object> config = Map.of("provider", "console", "fromEmail", "noreply@test.com");
            when(emailTestService.getEmailConfiguration()).thenReturn(config);

            final ResponseEntity<Map<String, Object>> response = controller.getEmailConfig();

            assertThat(response.getBody()).isEqualTo(config);
        }

        @Test
        void callsGetEmailConfigurationOnce() throws Exception {
            when(emailTestService.getEmailConfiguration()).thenReturn(Map.of());

            controller.getEmailConfig();

            verify(emailTestService, times(1)).getEmailConfiguration();
        }
    }

    // ── GET /v1/api/email-test/validate ──────────────────────────────────────

    @Nested
    class ValidateEmailConfiguration {

        @Test
        void returns200() throws Exception {
            when(emailTestService.validateEmailConfiguration()).thenReturn(Map.of());

            final ResponseEntity<Map<String, Object>> response = controller.validateEmailConfiguration();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final Map<String, Object> validation = Map.of("overallValid", true, "providerSet", true);
            when(emailTestService.validateEmailConfiguration()).thenReturn(validation);

            final ResponseEntity<Map<String, Object>> response = controller.validateEmailConfiguration();

            assertThat(response.getBody()).isEqualTo(validation);
        }

        @Test
        void callsValidateEmailConfigurationOnce() throws Exception {
            when(emailTestService.validateEmailConfiguration()).thenReturn(Map.of());

            controller.validateEmailConfiguration();

            verify(emailTestService, times(1)).validateEmailConfiguration();
        }
    }

    // ── POST /v1/api/email-test/all ───────────────────────────────────────────

    @Nested
    class TestAllEmailTypes {

        @Test
        void returns200_whenEmailIsValid() throws Exception {
            when(emailTestService.testAllEmailTypes(TEST_EMAIL)).thenReturn(Map.of());

            final ResponseEntity<Map<String, Object>> response =
                    controller.testAllEmailTypes(Map.of("email", TEST_EMAIL));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult_whenEmailIsValid() throws Exception {
            final Map<String, Object> results = Map.of(
                    "verificationEmail", "SUCCESS",
                    "passwordResetEmail", "SUCCESS",
                    "passwordSetupEmail", "SUCCESS");
            when(emailTestService.testAllEmailTypes(TEST_EMAIL)).thenReturn(results);

            final ResponseEntity<Map<String, Object>> response =
                    controller.testAllEmailTypes(Map.of("email", TEST_EMAIL));

            assertThat(response.getBody()).isEqualTo(results);
        }

        @Test
        void callsServiceWithCorrectEmail() throws Exception {
            when(emailTestService.testAllEmailTypes(TEST_EMAIL)).thenReturn(Map.of());

            controller.testAllEmailTypes(Map.of("email", TEST_EMAIL));

            verify(emailTestService).testAllEmailTypes(TEST_EMAIL);
        }

        @Test
        void returns400_whenEmailKeyAbsent() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.testAllEmailTypes(Collections.emptyMap());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void returns400_whenEmailIsNull() throws Exception {
            final Map<String, String> body = new HashMap<>();
            body.put("email", null);

            final ResponseEntity<Map<String, Object>> response = controller.testAllEmailTypes(body);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void returns400_whenEmailIsEmpty() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.testAllEmailTypes(Map.of("email", ""));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void returns400_whenEmailIsBlankWhitespace() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.testAllEmailTypes(Map.of("email", "   "));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void errorBodyContainsRequiredMessage_whenEmailMissing() throws Exception {
            final ResponseEntity<Map<String, Object>> response =
                    controller.testAllEmailTypes(Collections.emptyMap());

            assertThat(response.getBody())
                    .containsEntry("error", "Email address is required");
        }

        @Test
        void doesNotCallService_whenEmailIsNull() throws Exception {
            final Map<String, String> body = new HashMap<>();
            body.put("email", null);

            controller.testAllEmailTypes(body);

            verifyNoInteractions(emailTestService);
        }

        @Test
        void doesNotCallService_whenEmailIsEmpty() throws Exception {
            controller.testAllEmailTypes(Map.of("email", ""));

            verifyNoInteractions(emailTestService);
        }

        @Test
        void doesNotCallService_whenEmailIsBlank() throws Exception {
            controller.testAllEmailTypes(Map.of("email", "   "));

            verifyNoInteractions(emailTestService);
        }
    }

    // ── GET /v1/api/email-test/health ─────────────────────────────────────────

    @Nested
    class HealthCheck {

        @Test
        void returns200() throws Exception {
            when(emailTestService.getEmailConfiguration()).thenReturn(configMap(true));

            final ResponseEntity<Map<String, Object>> response = controller.healthCheck();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void statusIsUp_andHealthyIsTrue_whenConfigurationIsValid() throws Exception {
            when(emailTestService.getEmailConfiguration()).thenReturn(configMap(true));

            final Map<String, Object> body = controller.healthCheck().getBody();

            assertThat(body).containsEntry("status", "UP")
                    .containsEntry("healthy", true);
        }

        @Test
        void statusIsDown_andHealthyIsFalse_whenConfigurationIsInvalid() throws Exception {
            when(emailTestService.getEmailConfiguration()).thenReturn(configMap(false));

            final Map<String, Object> body = controller.healthCheck().getBody();

            assertThat(body).containsEntry("status", "DOWN")
                    .containsEntry("healthy", false);
        }

        @Test
        void bodyIncludesProviderFromConfig() throws Exception {
            final Map<String, Object> config = configMap(true);
            config.put("provider", "smtp");
            when(emailTestService.getEmailConfiguration()).thenReturn(config);

            final Map<String, Object> body = controller.healthCheck().getBody();

            assertThat(body).containsEntry("provider", "smtp");
        }

        @Test
        void bodyIncludesMailSenderAvailableFromConfig() throws Exception {
            final Map<String, Object> config = configMap(true);
            config.put("mailSenderAvailable", false);
            when(emailTestService.getEmailConfiguration()).thenReturn(config);

            final Map<String, Object> body = controller.healthCheck().getBody();

            assertThat(body).containsEntry("mailSenderAvailable", false);
        }

        @Test
        void callsGetEmailConfigurationOnce() throws Exception {
            when(emailTestService.getEmailConfiguration()).thenReturn(configMap(true));

            controller.healthCheck();

            verify(emailTestService, times(1)).getEmailConfiguration();
        }

        @Test
        void bodyContainsFourKeys() throws Exception {
            when(emailTestService.getEmailConfiguration()).thenReturn(configMap(true));

            final Map<String, Object> body = controller.healthCheck().getBody();

            // healthy, provider, mailSenderAvailable, status
            assertThat(body).containsKeys("healthy", "provider", "mailSenderAvailable", "status");
        }
    }

    // ── GET /v1/api/email-test/test-simple ───────────────────────────────────

    @Nested
    class TestSimpleEmail {

        @Test
        void returns200() throws Exception {
            when(emailTestService.testSimpleEmail(TEST_EMAIL)).thenReturn(Map.of());

            final ResponseEntity<Map<String, Object>> response = controller.testSimpleEmail(TEST_EMAIL);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult() throws Exception {
            final Map<String, Object> result = Map.of("success", true, "message", "Simple test email sent successfully");
            when(emailTestService.testSimpleEmail(TEST_EMAIL)).thenReturn(result);

            final ResponseEntity<Map<String, Object>> response = controller.testSimpleEmail(TEST_EMAIL);

            assertThat(response.getBody()).isEqualTo(result);
        }

        @Test
        void callsServiceWithCorrectEmail() throws Exception {
            when(emailTestService.testSimpleEmail(TEST_EMAIL)).thenReturn(Map.of());

            controller.testSimpleEmail(TEST_EMAIL);

            verify(emailTestService).testSimpleEmail(TEST_EMAIL);
        }

        @Test
        void callsServiceOnce() throws Exception {
            when(emailTestService.testSimpleEmail(TEST_EMAIL)).thenReturn(Map.of());

            controller.testSimpleEmail(TEST_EMAIL);

            verify(emailTestService, times(1)).testSimpleEmail(TEST_EMAIL);
        }
    }
}
