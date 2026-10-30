package com.careconnect.service;

import com.careconnect.controller.GoogleHealthOAuthCallbackController;
import com.careconnect.controller.GoogleHealthWearableController;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.security.TokenCryptor;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import java.net.URI;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class GoogleHealthOAuthServiceCoverageTest {

    @Mock private GoogleOAuthService googleOAuthService;
    @Mock private TokenCryptor tokenCryptor;
    @Mock private RestTemplate restTemplate;
    @Mock private SecurityUtil securityUtil;

    private GoogleHealthOAuthService service;

    @BeforeEach
    void setUp() {
        service = new GoogleHealthOAuthService(googleOAuthService, tokenCryptor, restTemplate);
        ReflectionTestUtils.setField(service, "clientId", "client-id");
        ReflectionTestUtils.setField(service, "redirectUri", "http://localhost/cb");
        ReflectionTestUtils.setField(service, "scope", "scope-a");
        ReflectionTestUtils.setField(service, "defaultFrontendReturnUrl", "http://localhost/wearables");
    }

    private static EmailCredential cred(String token) {
        EmailCredential c = new EmailCredential();
        c.setAccessTokenEnc(token);
        return c;
    }

    @Test
    void authorizationUrlAndCallbackRoundTripState() {
        String url = service.buildAuthorizationUrl("42", "http://app/return");
        assertThat(url).contains("client_id=client-id");
        assertThat(service.buildAuthorizationUrl("42", null)).contains("state=");

        String encoded = java.util.Base64.getUrlEncoder().withoutPadding()
                .encodeToString("http://app/return".getBytes());
        GoogleHealthOAuthService.OAuthCallbackResult result = service.handleCallback("code", "u:42|r:" + encoded);
        assertThat(result.userId()).isEqualTo("42");
        assertThat(result.returnUrl()).isEqualTo("http://app/return");
        verify(googleOAuthService).exchange(eq("42"), eq("code"), any(), eq("http://localhost/cb"));

        assertThatThrownBy(() -> service.handleCallback("c", null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.handleCallback("c", "r:abc|x:1")).isInstanceOf(IllegalArgumentException.class);
        assertThat(service.defaultReturnUrl()).isEqualTo("http://localhost/wearables");
    }

    @Test
    void connectionStatusDisconnectAndExerciseData() {
        when(googleOAuthService.findLatestCredential(eq("1"), any())).thenReturn(Optional.of(cred("enc")));
        when(googleOAuthService.findLatestCredential(eq("2"), any())).thenReturn(Optional.of(cred(" ")));
        when(googleOAuthService.findLatestCredential(eq("3"), any())).thenReturn(Optional.empty());
        assertThat(service.isConnected("1")).isTrue();
        assertThat(service.isConnected("2")).isFalse();
        service.disconnect("1");
        verify(googleOAuthService).disconnect(eq("1"), any());

        when(googleOAuthService.ensureFreshToken(any())).thenAnswer(inv -> inv.getArgument(0));
        when(tokenCryptor.decrypt("enc")).thenReturn("plain");
        when(restTemplate.exchange(any(URI.class), eq(HttpMethod.GET), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(ResponseEntity.ok(Map.of("dataPoints", 1)))
                .thenReturn(ResponseEntity.status(HttpStatus.BAD_GATEWAY).build());
        assertThat(service.listExerciseDataPoints("1", 10, "tok", "f")).containsKey("dataPoints");
        assertThatThrownBy(() -> service.listExerciseDataPoints("1", null, null, null))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> service.listExerciseDataPoints("2", 0, " ", " "))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> service.listExerciseDataPoints("3", null, null, null))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void wearableControllerEndpoints() {
        GoogleHealthOAuthService svc = org.mockito.Mockito.mock(GoogleHealthOAuthService.class);
        GoogleHealthWearableController controller = new GoogleHealthWearableController(svc, securityUtil);
        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        assertThat(controller.authUrl(null).getStatusCode().value()).isEqualTo(401);
        assertThat(controller.start(null).getStatusCode().value()).isEqualTo(401);
        assertThat(controller.status().getStatusCode().value()).isEqualTo(401);
        assertThat(controller.disconnect().getStatusCode().value()).isEqualTo(401);
        assertThat(controller.exerciseData(null, null, null).getStatusCode().value()).isEqualTo(401);

        when(securityUtil.resolveCurrentUser()).thenReturn(User.builder().id(7L).build());
        when(svc.buildAuthorizationUrl("7", "r")).thenReturn("http://auth/url");
        when(svc.listExerciseDataPoints("7", 5, null, null)).thenReturn(Map.of());
        assertThat(controller.authUrl("r").getStatusCode().value()).isEqualTo(200);
        assertThat(controller.start("r").getStatusCode().value()).isEqualTo(302);
        assertThat(controller.status().getStatusCode().value()).isEqualTo(200);
        assertThat(controller.disconnect().getStatusCode().value()).isEqualTo(200);
        assertThat(controller.exerciseData(5, null, null).getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void callbackControllerRedirects() {
        GoogleHealthOAuthService svc = org.mockito.Mockito.mock(GoogleHealthOAuthService.class);
        GoogleHealthOAuthCallbackController controller = new GoogleHealthOAuthCallbackController(svc);
        when(svc.defaultReturnUrl()).thenReturn("http://localhost/wearables");
        assertThat(controller.callback(null, null, "denied").getHeaders().getLocation().toString())
                .contains("googleHealthError=denied");
        assertThat(controller.callback(null, "s", null).getHeaders().getLocation().toString())
                .contains("missing_callback_params");
        when(svc.handleCallback("c", "s"))
                .thenReturn(new GoogleHealthOAuthService.OAuthCallbackResult("1", "http://app/x?y=1"));
        assertThat(controller.callback("c", "s", null).getHeaders().getLocation().toString())
                .contains("&googleHealth=connected");
        when(svc.handleCallback("c", "t")).thenReturn(new GoogleHealthOAuthService.OAuthCallbackResult("1", null));
        assertThat(controller.callback("c", "t", null).getStatusCode().value()).isEqualTo(302);
        doThrow(new IllegalArgumentException("bad state")).when(svc).handleCallback("c", "bad");
        assertThat(controller.callback("c", "bad", null).getHeaders().getLocation().toString())
                .contains("googleHealthError=bad");
    }
}
