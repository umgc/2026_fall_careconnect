package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.careconnect.dto.ehr.EpicTokenResponse;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.ehr.EhrCredentialRepository;
import com.careconnect.security.TokenCryptor;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link EpicOAuthService} — the two highest-risk pieces of the Epic SMART-on-FHIR
 * surface (authorize-URL + PKCE assembly, and the code→token exchange). The {@link RestTemplate} is
 * mocked, so no network is touched. Closes review Gap 1 (EpicOAuthServiceTest was missing).
 */
class EpicOAuthServiceTest {

    private static final String FHIR_BASE =
            "https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4";
    private static final String OAUTH_BASE =
            "https://fhir.epic.com/interconnect-fhir-oauth";

    private final RestTemplate http = mock(RestTemplate.class);
    private final EpicProperties cfg = mock(EpicProperties.class);
    private final TokenCryptor tokenCryptor = mock(TokenCryptor.class);
    private final EhrCredentialRepository credRepo = mock(EhrCredentialRepository.class);
    private final EhrAuditService audit = mock(EhrAuditService.class);

    private EpicOAuthService newService() {
        return new EpicOAuthService(http, cfg, tokenCryptor, credRepo, audit);
    }

    private void stubCommonConfig() {
        when(cfg.getFhirBaseUrl()).thenReturn(FHIR_BASE);
        when(cfg.getClientId()).thenReturn("client-123");
        when(cfg.getRedirectUri()).thenReturn("http://localhost:8081/api/epic/callback");
        when(cfg.getScopes()).thenReturn("openid fhirUser patient/Patient.read");
    }

    // ---- authorize URL + PKCE --------------------------------------------

    @Test
    void buildAuthorizeUrl_carriesPkceChallengeAndRequiredEpicParams() {
        stubCommonConfig();
        // Discovery unreachable -> derived Epic defaults.
        when(http.getForObject(anyString(), eq(JsonNode.class))).thenReturn(null);

        String url = newService().buildAuthorizeUrl("state-xyz", "challenge-abc");

        assertThat(url).startsWith(OAUTH_BASE + "/oauth2/authorize");
        assertThat(url).contains("response_type=code");
        assertThat(url).contains("client_id=client-123");
        assertThat(url).contains("state=state-xyz");
        assertThat(url).contains("code_challenge=challenge-abc");
        assertThat(url).contains("code_challenge_method=S256");
        // Epic requires aud = FHIR base. encode() only escapes illegal chars: the space-delimited
        // scope becomes %20-separated (the bug build(true) would have thrown on), while ':' and '/'
        // stay literal in aud/scope since they are legal in a query value.
        assertThat(url).contains("aud=https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4");
        assertThat(url).contains("scope=openid%20fhirUser%20patient/Patient.read");
    }

    @Test
    void buildAuthorizeUrl_prefersDiscoveredAuthorizeEndpoint() throws Exception {
        stubCommonConfig();
        JsonNode discovery = new ObjectMapper().readTree(
                "{\"authorization_endpoint\":\"https://disc.example/oauth2/authorize\","
                        + "\"token_endpoint\":\"https://disc.example/oauth2/token\"}");
        when(http.getForObject(anyString(), eq(JsonNode.class))).thenReturn(discovery);

        String url = newService().buildAuthorizeUrl("s", "c");

        assertThat(url).startsWith("https://disc.example/oauth2/authorize");
    }

    @Test
    void authorizeUrl_fallsBackToDerivedEndpoints_whenDiscoveryThrows() {
        stubCommonConfig();
        when(http.getForObject(anyString(), eq(JsonNode.class)))
                .thenThrow(new RuntimeException("connection refused"));

        String url = newService().buildAuthorizeUrl("s", "c");

        assertThat(url).startsWith(OAUTH_BASE + "/oauth2/authorize");
    }

    // ---- token exchange request shape + persistence ----------------------

    @Test
    @SuppressWarnings("unchecked")
    void exchangeAndStore_confidentialClient_usesBasicAuth_noClientIdInBody_persistsEncrypted() {
        stubCommonConfig();
        when(cfg.isConfidentialClient()).thenReturn(true);
        when(cfg.getClientSecret()).thenReturn("s3cr3t");
        when(http.getForObject(anyString(), eq(JsonNode.class))).thenReturn(null); // fallback token url
        when(credRepo.findFirstByUserIdAndSourceOrderByIdDesc(7L, EpicProperties.SOURCE_EPIC))
                .thenReturn(Optional.empty());
        when(credRepo.save(any(EhrCredential.class))).thenAnswer(inv -> inv.getArgument(0));
        when(tokenCryptor.encrypt("access-tok")).thenReturn("ENC(access)");
        when(tokenCryptor.encrypt("refresh-tok")).thenReturn("ENC(refresh)");
        when(http.postForEntity(anyString(), any(HttpEntity.class), eq(EpicTokenResponse.class)))
                .thenReturn(ResponseEntity.ok(new EpicTokenResponse(
                        "access-tok", "refresh-tok", "Bearer", 3600L,
                        "patient/Patient.read", "Patient/eXYZ")));

        EhrCredential saved = newService().exchangeAndStore(7L, "auth-code", "verifier-1");

        ArgumentCaptor<HttpEntity<MultiValueMap<String, String>>> captor =
                ArgumentCaptor.forClass(HttpEntity.class);
        verify(http).postForEntity(eq(OAUTH_BASE + "/oauth2/token"), captor.capture(),
                eq(EpicTokenResponse.class));
        HttpEntity<MultiValueMap<String, String>> req = captor.getValue();
        // Confidential client: Basic auth header present, client_id NOT in the form body.
        assertThat(req.getHeaders().getFirst(HttpHeaders.AUTHORIZATION)).startsWith("Basic ");
        assertThat(req.getBody().getFirst("client_id")).isNull();
        assertThat(req.getBody().getFirst("grant_type")).isEqualTo("authorization_code");
        assertThat(req.getBody().getFirst("code")).isEqualTo("auth-code");
        assertThat(req.getBody().getFirst("code_verifier")).isEqualTo("verifier-1");

        // Persisted credential: encrypted tokens, patient id, ACTIVE, future expiry.
        assertThat(saved.getUserId()).isEqualTo(7L);
        assertThat(saved.getSource()).isEqualTo(EpicProperties.SOURCE_EPIC);
        assertThat(saved.getPatientFhirId()).isEqualTo("Patient/eXYZ");
        assertThat(saved.getAccessTokenEnc()).isEqualTo("ENC(access)");
        assertThat(saved.getRefreshTokenEnc()).isEqualTo("ENC(refresh)");
        assertThat(saved.getStatus()).isEqualTo(EhrCredential.Status.ACTIVE);
        assertThat(saved.getExpiresAt()).isAfter(Instant.now());
        verify(credRepo).save(any(EhrCredential.class));
    }

    @Test
    @SuppressWarnings("unchecked")
    void exchangeAndStore_publicClient_putsClientIdInBody_noBasicAuth() {
        stubCommonConfig();
        when(cfg.isConfidentialClient()).thenReturn(false);
        when(http.getForObject(anyString(), eq(JsonNode.class))).thenReturn(null);
        when(credRepo.findFirstByUserIdAndSourceOrderByIdDesc(anyLong(), anyString()))
                .thenReturn(Optional.empty());
        when(credRepo.save(any(EhrCredential.class))).thenAnswer(inv -> inv.getArgument(0));
        when(tokenCryptor.encrypt(anyString())).thenReturn("ENC");
        when(http.postForEntity(anyString(), any(HttpEntity.class), eq(EpicTokenResponse.class)))
                .thenReturn(ResponseEntity.ok(new EpicTokenResponse(
                        "a", null, "Bearer", 3600L, null, "Patient/1")));

        newService().exchangeAndStore(9L, "code", "verifier");

        ArgumentCaptor<HttpEntity<MultiValueMap<String, String>>> captor =
                ArgumentCaptor.forClass(HttpEntity.class);
        verify(http).postForEntity(anyString(), captor.capture(), eq(EpicTokenResponse.class));
        HttpEntity<MultiValueMap<String, String>> req = captor.getValue();
        assertThat(req.getBody().getFirst("client_id")).isEqualTo("client-123");
        assertThat(req.getHeaders().getFirst(HttpHeaders.AUTHORIZATION)).isNull();
    }

    @Test
    @SuppressWarnings("unchecked")
    void exchangeAndStore_whenNoAccessToken_auditsErrorAndThrows_withoutPersisting() {
        stubCommonConfig();
        when(cfg.isConfidentialClient()).thenReturn(false);
        when(http.getForObject(anyString(), eq(JsonNode.class))).thenReturn(null);
        when(http.postForEntity(anyString(), any(HttpEntity.class), eq(EpicTokenResponse.class)))
                .thenReturn(ResponseEntity.ok(new EpicTokenResponse(
                        null, null, "Bearer", 3600L, null, null)));

        assertThatThrownBy(() -> newService().exchangeAndStore(5L, "code", "verifier"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("no access token");

        verify(credRepo, never()).save(any(EhrCredential.class));
        verify(audit).record(eq(5L), eq(EpicProperties.SOURCE_EPIC), eq("EPIC_CONNECT"),
                eq(EpicProperties.SOURCE_EPIC), isNull(), eq("ERROR"));
    }
}
