package com.careconnect.service;

import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.LinkOutcome;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2RefreshToken;
import org.springframework.security.web.authentication.AuthenticationFailureHandler;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.stereotype.Service;
import org.springframework.web.util.UriComponentsBuilder;

import java.io.IOException;

/**
 * Finishes (or abandons) a Medicare link when Blue Button redirects back to
 * {@code /login/oauth2/code/medicare}, then sends the browser back to the app with the outcome in a
 * {@code ?medicare=} query parameter.
 *
 * <p>The sign-in at Medicare is used only to obtain tokens, never as a CareConnect login. So once
 * the tokens are stored, everything the OAuth flow left behind is discarded: the authorized client
 * Spring keeps in memory, the security context, and the session. Nothing a later request presents
 * can be mistaken for an authenticated CareConnect user.
 */
@Slf4j
@Service
public class OAuthHelperService implements AuthenticationSuccessHandler, AuthenticationFailureHandler {

    /** Session attribute that carries the link token from {@code /oauth2/connect} to the callback. */
    public static final String LINK_TOKEN_SESSION_ATTRIBUTE = "medicare.linkToken";

    private final MedicareConnectionService connections;
    private final ObjectProvider<OAuth2AuthorizedClientService> authorizedClientsProvider;
    private final String frontendBaseUrl;

    /**
     * The authorized-client store is looked up lazily: it only exists where Spring's OAuth client
     * auto-configuration runs, and several integration tests switch that off.
     */
    public OAuthHelperService(
            final MedicareConnectionService connections,
            final ObjectProvider<OAuth2AuthorizedClientService> authorizedClients,
            @Value("${frontend.base-url}") final String frontendBaseUrl) {
        this.connections = connections;
        this.authorizedClientsProvider = authorizedClients;
        this.frontendBaseUrl = frontendBaseUrl;
    }

    @Override
    public void onAuthenticationSuccess(
            final HttpServletRequest request, final HttpServletResponse response, final Authentication authentication)
            throws IOException {
        final OAuth2AuthenticationToken oauth = (OAuth2AuthenticationToken) authentication;
        final String registrationId = oauth.getAuthorizedClientRegistrationId();
        final String principalName = oauth.getName();
        final OAuth2AuthorizedClientService authorizedClients = authorizedClientsProvider.getIfAvailable();
        LinkOutcome outcome = LinkOutcome.LINK_EXPIRED;
        try {
            if (MedicareConnectionService.REGISTRATION_ID.equals(registrationId)) {
                final OAuth2AuthorizedClient client = authorizedClients == null
                        ? null
                        : authorizedClients.loadAuthorizedClient(registrationId, principalName);
                final OAuth2RefreshToken refresh = client == null ? null : client.getRefreshToken();
                outcome = client == null
                        ? LinkOutcome.LINK_EXPIRED
                        : connections.completeLink(
                                linkToken(request),
                                principalName,
                                client.getAccessToken().getTokenValue(),
                                client.getAccessToken().getExpiresAt(),
                                refresh == null ? null : refresh.getTokenValue());
            }
            // Registration id and outcome only: never tokens, the beneficiary id or session ids.
            log.info("OAuth link callback for '{}': {}", registrationId, outcome.code());
        } finally {
            if (authorizedClients != null) {
                authorizedClients.removeAuthorizedClient(registrationId, principalName);
            }
            discardSession(request);
        }
        redirect(response, outcome.code());
    }

    @Override
    public void onAuthenticationFailure(
            final HttpServletRequest request, final HttpServletResponse response, final AuthenticationException exception)
            throws IOException {
        // access_denied is the patient pressing Cancel or Deny at Medicare (FR-MCR-05).
        final boolean cancelled = exception instanceof OAuth2AuthenticationException oauthException
                && "access_denied".equals(oauthException.getError().getErrorCode());
        log.info("OAuth link callback failed: {}", cancelled ? "cancelled by the patient" : exception.getClass().getSimpleName());
        try {
            connections.abandonLink(linkToken(request));
        } finally {
            discardSession(request);
        }
        redirect(response, cancelled ? "cancelled" : "failed");
    }

    private static String linkToken(final HttpServletRequest request) {
        final HttpSession session = request.getSession(false);
        final Object token = session == null ? null : session.getAttribute(LINK_TOKEN_SESSION_ATTRIBUTE);
        return token == null ? null : token.toString();
    }

    private static void discardSession(final HttpServletRequest request) {
        SecurityContextHolder.clearContext();
        final HttpSession session = request.getSession(false);
        if (session != null) {
            session.invalidate();
        }
    }

    private void redirect(final HttpServletResponse response, final String code) throws IOException {
        response.sendRedirect(UriComponentsBuilder.fromUriString(frontendBaseUrl)
                .queryParam("medicare", code)
                .build()
                .toUriString());
    }
}
