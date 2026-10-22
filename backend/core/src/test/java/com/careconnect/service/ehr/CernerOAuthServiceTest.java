package com.careconnect.service.ehr;

import com.careconnect.config.CernerProperties;
import com.careconnect.dto.ehr.CernerTokenResponse;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.ehr.EhrCredentialRepository;
import com.careconnect.security.TokenCryptor;
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
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CernerOAuthServiceTest {

    private static final String FHIR_BASE = "https://fhir-ehr-code.cerner.com/r4/tenant";
    private static final String AUTHORIZE = "https://authorization.cerner.com/authorize";
    private static final String TOKEN = "https://authorization.cerner.com/token";

    private final RestTemplate http = mock(RestTemplate.class);
    private final CernerProperties config = mock(CernerProperties.class);
    private final TokenCryptor cryptor = mock(TokenCryptor.class);
    private final EhrCredentialRepository credentials = mock(EhrCredentialRepository.class);
    private final EhrAuditService audit = mock(EhrAuditService.class);

    private CernerOAuthService service() {
        when(config.getFhirBaseUrl()).thenReturn(FHIR_BASE);
        when(config.getClientId()).thenReturn("oracle-client");
        when(config.getRedirectUri()).thenReturn("https://careconnect.example/api/oracle-health/callback");
        when(config.getScopes()).thenReturn(
                "openid fhirUser launch/patient patient/AllergyIntolerance.read");
        when(config.getAuthorizationEndpoint()).thenReturn(AUTHORIZE);
        when(config.getTokenEndpoint()).thenReturn(TOKEN);
        return new CernerOAuthService(http, config, cryptor, credentials, audit);
    }

    @Test
    void authorizeUrlCarriesAudPkceAndOptionalLaunchContext() {
        String url = service().buildAuthorizeUrl("state-1", "challenge-1", "launch-1");

        assertThat(url).startsWith(AUTHORIZE);
        assertThat(url).contains("client_id=oracle-client");
        assertThat(url).contains("state=state-1");
        assertThat(url).contains("code_challenge=challenge-1");
        assertThat(url).contains("code_challenge_method=S256");
        assertThat(url).contains("launch=launch-1");
        assertThat(url).contains("aud=" + FHIR_BASE);
        assertThat(url).contains("scope=openid%20fhirUser%20launch%20patient/AllergyIntolerance.read");
    }

    @Test
    @SuppressWarnings("unchecked")
    void publicClientExchangeStoresEncryptedOracleHealthCredential() {
        when(config.isConfidentialClient()).thenReturn(false);
        when(credentials.findFirstByUserIdAndSourceOrderByIdDesc(
                7L, CernerProperties.SOURCE_ORACLE_HEALTH)).thenReturn(Optional.empty());
        when(credentials.save(any(EhrCredential.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(cryptor.encrypt("access-token")).thenReturn("encrypted-access");
        when(cryptor.encrypt("refresh-token")).thenReturn("encrypted-refresh");
        when(http.postForEntity(eq(TOKEN), any(HttpEntity.class), eq(CernerTokenResponse.class)))
                .thenReturn(ResponseEntity.ok(new CernerTokenResponse(
                        "access-token", "refresh-token", "Bearer", 300L,
                        "patient/AllergyIntolerance.read", "12724066")));

        EhrCredential stored = service().exchangeAndStore(7L, "code-1", "verifier-1");

        assertThat(stored.getSource()).isEqualTo(CernerProperties.SOURCE_ORACLE_HEALTH);
        assertThat(stored.getPatientFhirId()).isEqualTo("12724066");
        assertThat(stored.getAccessTokenEnc()).isEqualTo("encrypted-access");
        assertThat(stored.getRefreshTokenEnc()).isEqualTo("encrypted-refresh");
        assertThat(stored.getExpiresAt()).isAfter(Instant.now());

        ArgumentCaptor<HttpEntity<MultiValueMap<String, String>>> request =
                ArgumentCaptor.forClass(HttpEntity.class);
        verify(http).postForEntity(eq(TOKEN), request.capture(), eq(CernerTokenResponse.class));
        assertThat(request.getValue().getBody().getFirst("client_id")).isEqualTo("oracle-client");
        assertThat(request.getValue().getBody().getFirst("code_verifier")).isEqualTo("verifier-1");
        assertThat(request.getValue().getHeaders().getFirst(HttpHeaders.AUTHORIZATION)).isNull();
    }

    @Test
    void validUnexpiredTokenIsDecryptedWithoutRefresh() {
        EhrCredential credential = EhrCredential.builder()
                .userId(9L)
                .source(CernerProperties.SOURCE_ORACLE_HEALTH)
                .status(EhrCredential.Status.ACTIVE)
                .accessTokenEnc("encrypted")
                .expiresAt(Instant.now().plusSeconds(600))
                .build();
        when(credentials.findFirstByUserIdAndSourceOrderByIdDesc(
                9L, CernerProperties.SOURCE_ORACLE_HEALTH)).thenReturn(Optional.of(credential));
        when(cryptor.decrypt("encrypted")).thenReturn("plain-token");

        assertThat(service().validAccessToken(9L)).isEqualTo("plain-token");
    }

    @Test
    void expiredCredentialWithoutRefreshTokenIsMarkedForReauthorization() {
        EhrCredential credential = EhrCredential.builder()
                .userId(11L)
                .source(CernerProperties.SOURCE_ORACLE_HEALTH)
                .status(EhrCredential.Status.ACTIVE)
                .accessTokenEnc("expired")
                .expiresAt(Instant.now().minusSeconds(1))
                .build();
        when(credentials.findFirstByUserIdAndSourceOrderByIdDesc(
                11L, CernerProperties.SOURCE_ORACLE_HEALTH)).thenReturn(Optional.of(credential));
        when(credentials.save(any(EhrCredential.class))).thenAnswer(invocation -> invocation.getArgument(0));

        assertThatThrownBy(() -> service().validAccessToken(11L))
                .isInstanceOf(CernerOAuthService.CernerReauthorizationRequiredException.class);
        assertThat(credential.getStatus()).isEqualTo(EhrCredential.Status.NEEDS_REAUTH);
        verify(credentials).save(credential);
    }
}
