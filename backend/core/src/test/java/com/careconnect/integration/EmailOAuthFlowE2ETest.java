package com.careconnect.integration;

import com.careconnect.config.CareconnectTestConfig;
import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.notifications.SnsService;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.OAuthStateSigner;
import com.careconnect.security.Role;
import com.careconnect.service.GoogleOAuthService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.chimesdkmeetings.ChimeSdkMeetingsClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.iam.IamClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.textract.TextractClient;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end integration tests for PR #235: HMAC-signed OAuth state,
 * structured connection status, and Gmail disconnect flow.
 *
 * Covers the full OAuth lifecycle:
 *   GET connect-url → GET /oauth/google/start → GET /oauth/google/callback
 *   → GET /v1/api/email-credentials/status → DELETE /v1/api/email-credentials/gmail
 *
 * Uses:
 *   - @SpringBootTest (full application context, H2 in-memory DB)
 *   - MockMvc for HTTP assertions
 *   - Real OAuthStateSigner/OAuthRedirectValidator beans (exercises actual HMAC logic)
 *   - Mocked GoogleOAuthService (no real Google token exchange)
 *   - Mocked EmailCredentialRepository (controls credential state per scenario)
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.autoconfigure.exclude=" +
                        "org.springframework.boot.autoconfigure.security.oauth2.client.servlet.OAuth2ClientAutoConfiguration," +
                        "org.springframework.boot.autoconfigure.security.oauth2.resource.servlet.OAuth2ResourceServerAutoConfiguration"
        }
)
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(CareconnectTestConfig.class)
@DisplayName("PR #235 — Gmail OAuth E2E Tests")
class EmailOAuthFlowE2ETest {

    // ── AWS SDK mocks (required so full context loads without real credentials) ──

    @MockitoBean private ChimeSdkMeetingsClient chimeSdkMeetingsClient;
    @MockitoBean private ChimeSdkMediaPipelinesClient chimeSdkMediaPipelinesClient;
    @MockitoBean private BedrockRuntimeClient bedrockRuntimeClient;
    @MockitoBean private S3Client s3Client;
    @MockitoBean private S3Presigner s3Presigner;
    @MockitoBean private TextractClient textractClient;
    @MockitoBean private SsmClient ssmClient;
    @MockitoBean private StsClient stsClient;
    @MockitoBean private IamClient iamClient;
    @MockitoBean private SnsService snsService;

    // ── Conditional services disabled in test profile ────────────────────────────

    @MockitoBean private com.careconnect.service.OpenRouterService openRouterService;
    @MockitoBean private dev.langchain4j.model.chat.ChatModel chatModel;
    @MockitoBean(name = "mockAIChatService") private com.careconnect.service.AIChatService aiChatService;
    @MockitoBean private com.careconnect.service.invoice.TextractService textractService;
    @MockitoBean private com.careconnect.service.invoice.LlmExtractionService llmExtractionService;
    @MockitoBean private com.careconnect.service.StripeService stripeService;
    @MockitoBean private com.careconnect.service.SubscriptionService subscriptionService;
    @MockitoBean private com.careconnect.service.DeepSeekService deepSeekService;
    @MockitoBean private com.careconnect.service.AiSymptomService aiSymptomService;
    @MockitoBean private com.careconnect.service.AiAllergyService aiAllergyService;
    @MockitoBean private com.careconnect.service.S3StorageService s3StorageService;
    @MockitoBean private com.careconnect.service.ParameterStoreService parameterStoreService;

    // ── PR #235 service mocks ────────────────────────────────────────────────────

    /** Mocked so no real Google token exchange occurs. */
    @MockitoBean private GoogleOAuthService googleOAuthService;

    /** Mocked so each test scenario controls the stored credential state. */
    @MockitoBean private EmailCredentialRepository emailCredentialRepository;

    // ── Spring-managed beans ─────────────────────────────────────────────────────

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private OAuthStateSigner oauthStateSigner;
    @Autowired private ObjectMapper objectMapper;

    // ── Test fixtures ────────────────────────────────────────────────────────────

    private static final String ADMIN_EMAIL   = "admin@e2e-oauth.test";
    private static final String PATIENT_EMAIL = "patient@e2e-oauth.test";
    private static final String RETURN_URL    = "http://localhost:3000/usps-test";
    private static final String AUTH_CODE     = "google-auth-code-abc123";

    private User adminUser;
    private User patientUser;

    @BeforeEach
    void setUp() {
        adminUser = userRepository.findByEmail(ADMIN_EMAIL).orElseGet(() -> {
            User u = new User();
            u.setEmail(ADMIN_EMAIL);
            u.setPassword("hashed");
            u.setRole(Role.ADMIN);
            u.setName("E2E Admin");
            return userRepository.save(u);
        });

        patientUser = userRepository.findByEmail(PATIENT_EMAIL).orElseGet(() -> {
            User u = new User();
            u.setEmail(PATIENT_EMAIL);
            u.setPassword("hashed");
            u.setRole(Role.PATIENT);
            u.setName("E2E Patient");
            return userRepository.save(u);
        });

        // Default: no stored credential
        when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(anyString(), any()))
                .thenReturn(Optional.empty());
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 1. GET /v1/api/email-credentials/gmail/connect-url
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /v1/api/email-credentials/gmail/connect-url")
    class ConnectUrlTests {

        @Test
        @DisplayName("connectUrl_whenAuthenticated_returns200WithStartTokenUrl")
        void connectUrl_whenAuthenticated_returns200WithStartTokenUrl() throws Exception {
            MvcResult result = mockMvc.perform(get("/v1/api/email-credentials/gmail/connect-url")
                            .param("patientEmail", ADMIN_EMAIL)
                            .param("returnUrl", RETURN_URL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN"))
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.url").exists())
                    .andReturn();

            String body = result.getResponse().getContentAsString();
            assertThat(body).contains("/oauth/google/start");
            assertThat(body).contains("startToken=");
        }

        @Test
        @DisplayName("connectUrl_withoutReturnUrl_returns200WithDefaultUrl")
        void connectUrl_withoutReturnUrl_returns200WithDefaultUrl() throws Exception {
            mockMvc.perform(get("/v1/api/email-credentials/gmail/connect-url")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN"))
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.url").exists());
        }

        @Test
        @DisplayName("connectUrl_whenUnauthenticated_returns401")
        void connectUrl_whenUnauthenticated_returns401() throws Exception {
            mockMvc.perform(get("/v1/api/email-credentials/gmail/connect-url")
                            .param("patientEmail", ADMIN_EMAIL))
                    .andExpect(status().isUnauthorized());
        }

        @Test
        @DisplayName("connectUrl_startTokenIsShortLived_canBeUsedWithStartEndpoint")
        void connectUrl_startTokenIsShortLived_canBeUsedWithStartEndpoint() throws Exception {
            // Obtain start token via API
            MvcResult connectResult = mockMvc.perform(get("/v1/api/email-credentials/gmail/connect-url")
                            .param("patientEmail", ADMIN_EMAIL)
                            .param("returnUrl", RETURN_URL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN"))
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andReturn();

            String responseBody = connectResult.getResponse().getContentAsString();
            // Extract the startToken from the returned URL
            String url = objectMapper.readTree(responseBody).get("url").asText();
            String startToken = url.substring(url.indexOf("startToken=") + "startToken=".length());

            // Confirm the token is accepted by /oauth/google/start
            mockMvc.perform(get("/oauth/google/start").param("startToken", startToken))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("accounts.google.com");
                    });
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 2. GET /oauth/google/start  (public endpoint)
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /oauth/google/start")
    class OAuthStartTests {

        @Test
        @DisplayName("start_withValidStartToken_returns302ToGoogleAuth")
        void start_withValidStartToken_returns302ToGoogleAuth() throws Exception {
            String startToken = oauthStateSigner.signStartToken(String.valueOf(adminUser.getId()), RETURN_URL);

            mockMvc.perform(get("/oauth/google/start").param("startToken", startToken))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("accounts.google.com/o/oauth2/v2/auth");
                        assertThat(location).contains("client_id=stub");
                        assertThat(location).contains("state=");
                        assertThat(location).contains("access_type=offline");
                        assertThat(location).contains("prompt=consent");
                    });
        }

        @Test
        @DisplayName("start_locationContainsSignedStateNotRawStartToken")
        void start_locationContainsSignedStateNotRawStartToken() throws Exception {
            String startToken = oauthStateSigner.signStartToken(String.valueOf(adminUser.getId()), null);

            MvcResult result = mockMvc.perform(get("/oauth/google/start").param("startToken", startToken))
                    .andExpect(status().isFound())
                    .andReturn();

            String location = result.getResponse().getHeader("Location");
            // The state in the redirect must NOT be the original startToken — it is re-signed
            assertThat(location).doesNotContain(startToken);
            assertThat(location).contains("state=");
        }

        @Test
        @DisplayName("start_withMalformedToken_throwsException")
        void start_withMalformedToken_throwsException() throws Exception {
            mockMvc.perform(get("/oauth/google/start").param("startToken", "not-a-valid-token"))
                    .andExpect(status().is4xxClientError());
        }

        @Test
        @DisplayName("start_withCallbackStateUsedAsStartToken_throwsException")
        void start_withCallbackStateUsedAsStartToken_throwsException() throws Exception {
            // A full callback-state token must NOT be accepted as a startToken
            String callbackState = oauthStateSigner.sign(String.valueOf(adminUser.getId()), RETURN_URL);

            mockMvc.perform(get("/oauth/google/start").param("startToken", callbackState))
                    .andExpect(status().is4xxClientError());
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 3. GET /oauth/google/callback  (public endpoint)
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /oauth/google/callback")
    class OAuthCallbackTests {

        @Test
        @DisplayName("callback_withValidSignedState_exchangesCodeAndRedirectsToReturnUrl")
        void callback_withValidSignedState_exchangesCodeAndRedirectsToReturnUrl() throws Exception {
            String userId = String.valueOf(adminUser.getId());
            String state  = oauthStateSigner.sign(userId, RETURN_URL);

            doNothing().when(googleOAuthService).exchange(eq(userId), eq(AUTH_CODE));

            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", state))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).isEqualTo(RETURN_URL);
                    });

            verify(googleOAuthService).exchange(userId, AUTH_CODE);
        }

        @Test
        @DisplayName("callback_withValidStateAndNoReturnUrl_redirectsToDefaultUspsTestPage")
        void callback_withValidStateAndNoReturnUrl_redirectsToDefaultUspsTestPage() throws Exception {
            String state = oauthStateSigner.sign(String.valueOf(adminUser.getId()), null);

            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", state))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("/usps-test");
                        assertThat(location).doesNotContain("oauthError");
                    });
        }

        @Test
        @DisplayName("callback_withTamperedState_redirectsWithOauthError")
        void callback_withTamperedState_redirectsWithOauthError() throws Exception {
            String state = oauthStateSigner.sign(String.valueOf(adminUser.getId()), null) + "TAMPERED";

            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", state))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("oauthError=");
                        assertThat(location).doesNotContain("accounts.google.com");
                    });
        }

        @Test
        @DisplayName("callback_withLegacyUnsignedState_redirectsWithOauthError")
        void callback_withLegacyUnsignedState_redirectsWithOauthError() throws Exception {
            // Legacy format from before PR #235 — must be rejected
            String legacyState = "u:" + adminUser.getId() + "|r:" + RETURN_URL;

            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", legacyState))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("oauthError=");
                    });
        }

        @Test
        @DisplayName("callback_withStartTokenUsedAsCallbackState_redirectsWithOauthError")
        void callback_withStartTokenUsedAsCallbackState_redirectsWithOauthError() throws Exception {
            // Start tokens must NOT be accepted at the callback endpoint
            String startToken = oauthStateSigner.signStartToken(String.valueOf(adminUser.getId()), RETURN_URL);

            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", startToken))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("oauthError=");
                    });
        }

        @Test
        @DisplayName("callback_whenTokenExchangeFails_redirectsWithOauthErrorOnReturnUrl")
        void callback_whenTokenExchangeFails_redirectsWithOauthErrorOnReturnUrl() throws Exception {
            String state = oauthStateSigner.sign(String.valueOf(adminUser.getId()), RETURN_URL);

            doThrow(new RuntimeException("token exchange failed"))
                    .when(googleOAuthService).exchange(anyString(), eq(AUTH_CODE));

            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", state))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).startsWith(RETURN_URL);
                        assertThat(location).contains("oauthError=");
                        assertThat(location).contains("token+exchange+failed");
                    });
        }

        @Test
        @DisplayName("callback_errorParamIsOauthErrorNotLegacyError")
        void callback_errorParamIsOauthErrorNotLegacyError() throws Exception {
            String state = oauthStateSigner.sign(String.valueOf(adminUser.getId()), null);
            doThrow(new RuntimeException("boom")).when(googleOAuthService).exchange(anyString(), any());

            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", state))
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("oauthError=");
                        // Must not use the old "error=" param that the legacy code emitted
                        assertThat(location).doesNotContain("?error=");
                        assertThat(location).doesNotContain("&error=");
                    });
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 4. GET /v1/api/email-credentials/status
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("GET /v1/api/email-credentials/status")
    class ConnectionStatusTests {

        @Test
        @DisplayName("status_whenGmailConnectedAndTokenFresh_returnsConnectedStatus")
        void status_whenGmailConnectedAndTokenFresh_returnsConnectedStatus() throws Exception {
            EmailCredential cred = connectedCredential();
            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(String.valueOf(adminUser.getId())), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.of(cred));
            when(googleOAuthService.ensureFreshToken(cred)).thenReturn(true);

            // Second call after refresh
            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(String.valueOf(adminUser.getId())), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.of(cred));

            mockMvc.perform(get("/v1/api/email-credentials/status")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.connected").value(true))
                    .andExpect(jsonPath("$.status").value(EmailConnectionStatus.STATUS_CONNECTED))
                    .andExpect(jsonPath("$.provider").value("GMAIL"));
        }

        @Test
        @DisplayName("status_whenNoCredentialStored_returnsNotConnectedStatus")
        void status_whenNoCredentialStored_returnsNotConnectedStatus() throws Exception {
            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(String.valueOf(adminUser.getId())), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.empty());

            mockMvc.perform(get("/v1/api/email-credentials/status")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.connected").value(false))
                    .andExpect(jsonPath("$.status").value(EmailConnectionStatus.STATUS_NOT_CONNECTED))
                    .andExpect(jsonPath("$.provider").value("GMAIL"));
        }

        @Test
        @DisplayName("status_whenTokenRefreshFails_returnsNeedsReconnectStatus")
        void status_whenTokenRefreshFails_returnsNeedsReconnectStatus() throws Exception {
            EmailCredential cred = connectedCredential();
            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(String.valueOf(adminUser.getId())), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.of(cred));
            when(googleOAuthService.ensureFreshToken(cred)).thenReturn(false);

            mockMvc.perform(get("/v1/api/email-credentials/status")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.connected").value(false))
                    .andExpect(jsonPath("$.status").value(EmailConnectionStatus.STATUS_NEEDS_RECONNECT));
        }

        @Test
        @DisplayName("status_whenCredentialHasNoAccessToken_returnsNeedsReconnectStatus")
        void status_whenCredentialHasNoAccessToken_returnsNeedsReconnectStatus() throws Exception {
            EmailCredential cred = new EmailCredential();
            cred.setUserId(String.valueOf(adminUser.getId()));
            cred.setProvider(EmailCredential.Provider.GMAIL);
            // accessTokenEnc deliberately left null

            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(String.valueOf(adminUser.getId())), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.of(cred));

            mockMvc.perform(get("/v1/api/email-credentials/status")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.connected").value(false))
                    .andExpect(jsonPath("$.status").value(EmailConnectionStatus.STATUS_NEEDS_RECONNECT));
        }

        @Test
        @DisplayName("status_acceptsLegacyUserIdParam")
        void status_acceptsLegacyUserIdParam() throws Exception {
            mockMvc.perform(get("/v1/api/email-credentials/status")
                            .param("userId", String.valueOf(adminUser.getId()))
                            .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.connected").value(false));
        }

        @Test
        @DisplayName("status_whenUnauthenticated_returns401")
        void status_whenUnauthenticated_returns401() throws Exception {
            mockMvc.perform(get("/v1/api/email-credentials/status")
                            .param("patientEmail", ADMIN_EMAIL))
                    .andExpect(status().isUnauthorized());
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 5. DELETE /v1/api/email-credentials/gmail
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("DELETE /v1/api/email-credentials/gmail")
    class DisconnectTests {

        @Test
        @DisplayName("disconnect_whenCredentialExists_revokesAndReturns204")
        void disconnect_whenCredentialExists_revokesAndReturns204() throws Exception {
            EmailCredential cred = connectedCredential();
            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(String.valueOf(adminUser.getId())), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.of(cred));
            doNothing().when(googleOAuthService).revokeIfPossible(cred);

            mockMvc.perform(delete("/v1/api/email-credentials/gmail")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN"))
                            .with(csrf()))
                    .andExpect(status().isNoContent());

            verify(googleOAuthService).revokeIfPossible(cred);
            verify(emailCredentialRepository).delete(cred);
        }

        @Test
        @DisplayName("disconnect_whenNoCredentialExists_returns204WithNoAction")
        void disconnect_whenNoCredentialExists_returns204WithNoAction() throws Exception {
            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(String.valueOf(adminUser.getId())), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.empty());

            mockMvc.perform(delete("/v1/api/email-credentials/gmail")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN"))
                            .with(csrf()))
                    .andExpect(status().isNoContent());
        }

        @Test
        @DisplayName("disconnect_acceptsLegacyUserIdParam")
        void disconnect_acceptsLegacyUserIdParam() throws Exception {
            mockMvc.perform(delete("/v1/api/email-credentials/gmail")
                            .param("userId", String.valueOf(adminUser.getId()))
                            .with(user(ADMIN_EMAIL).roles("ADMIN"))
                            .with(csrf()))
                    .andExpect(status().isNoContent());
        }

        @Test
        @DisplayName("disconnect_whenUnauthenticated_returns401")
        void disconnect_whenUnauthenticated_returns401() throws Exception {
            mockMvc.perform(delete("/v1/api/email-credentials/gmail")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(csrf()))
                    .andExpect(status().isUnauthorized());
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 6. Full OAuth flow  — connect-url → start → callback → status → disconnect
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Full OAuth flow — happy path and replay-attack rejection")
    class FullFlowTests {

        @Test
        @DisplayName("fullFlow_connectUrlToCallbackToStatusToDisconnect_happyPath")
        void fullFlow_connectUrlToCallbackToStatusToDisconnect_happyPath() throws Exception {
            String adminId = String.valueOf(adminUser.getId());

            // Step 1 — get connect URL (authenticated)
            MvcResult connectResult = mockMvc.perform(
                            get("/v1/api/email-credentials/gmail/connect-url")
                                    .param("patientEmail", ADMIN_EMAIL)
                                    .param("returnUrl", RETURN_URL)
                                    .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andReturn();

            String connectUrl = objectMapper.readTree(connectResult.getResponse().getContentAsString())
                    .get("url").asText();
            assertThat(connectUrl).contains("/oauth/google/start?startToken=");
            String startToken = connectUrl.substring(connectUrl.indexOf("startToken=") + "startToken=".length());

            // Step 2 — follow public start link, get redirect to Google
            MvcResult startResult = mockMvc.perform(
                            get("/oauth/google/start").param("startToken", startToken))
                    .andExpect(status().isFound())
                    .andReturn();

            String googleUrl = startResult.getResponse().getHeader("Location");
            assertThat(googleUrl).contains("accounts.google.com");
            String signedState = extractQueryParam(googleUrl, "state");
            assertThat(signedState).isNotBlank();

            // Step 3 — simulate Google calling back with code + signed state
            doNothing().when(googleOAuthService).exchange(eq(adminId), eq(AUTH_CODE));

            MvcResult callbackResult = mockMvc.perform(
                            get("/oauth/google/callback")
                                    .param("code", AUTH_CODE)
                                    .param("state", signedState))
                    .andExpect(status().isFound())
                    .andReturn();

            String callbackRedirect = callbackResult.getResponse().getHeader("Location");
            assertThat(callbackRedirect).isEqualTo(RETURN_URL);
            assertThat(callbackRedirect).doesNotContain("oauthError");
            verify(googleOAuthService).exchange(adminId, AUTH_CODE);

            // Step 4 — check connection status (credential now "stored")
            EmailCredential storedCred = connectedCredential();
            when(emailCredentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                    eq(adminId), eq(EmailCredential.Provider.GMAIL)))
                    .thenReturn(Optional.of(storedCred));
            when(googleOAuthService.ensureFreshToken(storedCred)).thenReturn(true);

            mockMvc.perform(get("/v1/api/email-credentials/status")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.connected").value(true))
                    .andExpect(jsonPath("$.status").value(EmailConnectionStatus.STATUS_CONNECTED));

            // Step 5 — disconnect
            doNothing().when(googleOAuthService).revokeIfPossible(storedCred);

            mockMvc.perform(delete("/v1/api/email-credentials/gmail")
                            .param("patientEmail", ADMIN_EMAIL)
                            .with(user(ADMIN_EMAIL).roles("ADMIN"))
                            .with(csrf()))
                    .andExpect(status().isNoContent());

            verify(googleOAuthService).revokeIfPossible(storedCred);
            verify(emailCredentialRepository).delete(storedCred);
        }

        @Test
        @DisplayName("fullFlow_startTokenCannotBeReplayedAsCallbackState")
        void fullFlow_startTokenCannotBeReplayedAsCallbackState() throws Exception {
            // Obtain a real start token via the connect-url endpoint
            MvcResult connectResult = mockMvc.perform(
                            get("/v1/api/email-credentials/gmail/connect-url")
                                    .param("patientEmail", ADMIN_EMAIL)
                                    .with(user(ADMIN_EMAIL).roles("ADMIN")))
                    .andExpect(status().isOk())
                    .andReturn();

            String connectUrl = objectMapper.readTree(connectResult.getResponse().getContentAsString())
                    .get("url").asText();
            String startToken = connectUrl.substring(connectUrl.indexOf("startToken=") + "startToken=".length());

            // Attempt to replay the start token directly as the OAuth callback state (CSRF replay attack)
            mockMvc.perform(get("/oauth/google/callback")
                            .param("code", AUTH_CODE)
                            .param("state", startToken))
                    .andExpect(status().isFound())
                    .andExpect(result -> {
                        String location = result.getResponse().getHeader("Location");
                        assertThat(location).contains("oauthError=");
                    });
        }

        @Test
        @DisplayName("fullFlow_callbackStateCannotBeReusedAsStartToken")
        void fullFlow_callbackStateCannotBeReusedAsStartToken() throws Exception {
            // A callback-scoped signed state must not pass start-token verification
            String callbackState = oauthStateSigner.sign(String.valueOf(adminUser.getId()), RETURN_URL);

            mockMvc.perform(get("/oauth/google/start").param("startToken", callbackState))
                    .andExpect(status().is4xxClientError());
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────

    private EmailCredential connectedCredential() {
        EmailCredential cred = new EmailCredential();
        cred.setUserId(String.valueOf(adminUser.getId()));
        cred.setProvider(EmailCredential.Provider.GMAIL);
        cred.setAccessTokenEnc("encrypted-access-token");
        cred.setRefreshTokenEnc("encrypted-refresh-token");
        cred.setExpiresAt(Instant.now().plusSeconds(3600));
        return cred;
    }

    private static String extractQueryParam(String url, String param) {
        String search = param + "=";
        int start = url.indexOf(search);
        if (start < 0) return "";
        start += search.length();
        int end = url.indexOf('&', start);
        return end < 0 ? url.substring(start) : url.substring(start, end);
    }
}
