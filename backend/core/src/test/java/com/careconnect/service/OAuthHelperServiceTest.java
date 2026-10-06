package com.careconnect.service;

import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.LinkOutcome;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2RefreshToken;
import org.springframework.security.oauth2.core.user.DefaultOAuth2User;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** The Blue Button callback: store the link, discard the OAuth session, send the browser back to the app. */
class OAuthHelperServiceTest {

    private static final String FRONTEND = "http://localhost:3000";
    private static final String BENEFICIARY = "-20140000008325";

    private MedicareConnectionService connections;
    private OAuth2AuthorizedClientService authorizedClients;
    private OAuthHelperService handler;
    private MockHttpServletRequest request;
    private MockHttpSession session;
    private final MockHttpServletResponse response = new MockHttpServletResponse();

    @BeforeEach
    void setUp() {
        connections = mock(MedicareConnectionService.class);
        authorizedClients = mock(OAuth2AuthorizedClientService.class);
        handler = new OAuthHelperService(connections,
                new org.springframework.beans.factory.support.StaticListableBeanFactory(java.util.Map.of("authorizedClients", authorizedClients))
                        .getBeanProvider(OAuth2AuthorizedClientService.class),
                FRONTEND);
        session = new MockHttpSession();
        session.setAttribute(OAuthHelperService.LINK_TOKEN_SESSION_ATTRIBUTE, "link-token");
        request = new MockHttpServletRequest();
        request.setSession(session);
    }

    private static OAuth2AuthenticationToken login(final String registrationId) {
        final DefaultOAuth2User user = new DefaultOAuth2User(
                List.of(new SimpleGrantedAuthority("ROLE_PATIENT")), Map.of("sub", BENEFICIARY), "sub");
        return new OAuth2AuthenticationToken(user, user.getAuthorities(), registrationId);
    }

    private static OAuth2AuthorizedClient client(final Instant expiresAt, final String refresh) {
        final ClientRegistration registration = ClientRegistration.withRegistrationId("medicare")
                .clientId("id").authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .redirectUri("http://localhost:8080/login/oauth2/code/medicare")
                .authorizationUri("http://x/authorize").tokenUri("http://x/token").build();
        return new OAuth2AuthorizedClient(registration, BENEFICIARY,
                new OAuth2AccessToken(OAuth2AccessToken.TokenType.BEARER, "access", Instant.parse("2026-10-04T11:00:00Z"), expiresAt),
                refresh == null ? null : new OAuth2RefreshToken(refresh, null));
    }

    @Test
    @DisplayName("a Medicare callback completes the link with the session's link token, then discards the client and session")
    void successCompletesLink() throws Exception {
        final Instant expires = Instant.parse("2026-10-04T12:00:00Z");
        when(authorizedClients.loadAuthorizedClient("medicare", BENEFICIARY)).thenReturn(client(expires, "refresh"));
        when(connections.completeLink("link-token", BENEFICIARY, "access", expires, "refresh")).thenReturn(LinkOutcome.CONNECTED);

        handler.onAuthenticationSuccess(request, response, login("medicare"));

        verify(connections).completeLink("link-token", BENEFICIARY, "access", expires, "refresh");
        verify(authorizedClients).removeAuthorizedClient("medicare", BENEFICIARY);
        assertThat(session.isInvalid()).as("no session may outlive the link").isTrue();
        assertThat(response.getRedirectedUrl()).isEqualTo(FRONTEND + "?medicare=connected");
    }

    @Test
    @DisplayName("the outcome code reaches the app, e.g. a Medicare account already linked to someone else")
    void outcomeIsPassedOn() throws Exception {
        when(authorizedClients.loadAuthorizedClient("medicare", BENEFICIARY)).thenReturn(client(null, null));
        when(connections.completeLink("link-token", BENEFICIARY, "access", null, null)).thenReturn(LinkOutcome.ALREADY_LINKED_ELSEWHERE);

        handler.onAuthenticationSuccess(request, response, login("medicare"));

        assertThat(response.getRedirectedUrl()).isEqualTo(FRONTEND + "?medicare=already_linked");
    }

    @Test
    @DisplayName("a callback for any other registration links nothing, but still cleans up")
    void otherRegistrationLinksNothing() throws Exception {
        handler.onAuthenticationSuccess(request, response, login("google"));

        verify(connections, never()).completeLink(any(), any(), any(), any(), any());
        verify(authorizedClients).removeAuthorizedClient("google", BENEFICIARY);
        assertThat(session.isInvalid()).isTrue();
        assertThat(response.getRedirectedUrl()).isEqualTo(FRONTEND + "?medicare=link_expired");
    }

    @Test
    @DisplayName("FR-MCR-05: the patient denying at Medicare abandons the link and reports 'cancelled'")
    void deniedIsCancelled() throws Exception {
        handler.onAuthenticationFailure(request, response,
                new OAuth2AuthenticationException(new OAuth2Error("access_denied")));

        verify(connections).abandonLink("link-token");
        assertThat(session.isInvalid()).isTrue();
        assertThat(response.getRedirectedUrl()).isEqualTo(FRONTEND + "?medicare=cancelled");
    }

    @Test
    @DisplayName("FR-MCR-08: any other failure, such as the token exchange, abandons the link and reports 'failed'")
    void otherFailureIsFailed() throws Exception {
        handler.onAuthenticationFailure(request, response,
                new OAuth2AuthenticationException(new OAuth2Error("invalid_token_response")));

        verify(connections).abandonLink("link-token");
        assertThat(response.getRedirectedUrl()).isEqualTo(FRONTEND + "?medicare=failed");
    }
}
