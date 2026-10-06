package com.careconnect.controller.ehr;

import com.careconnect.exception.AppException;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.OAuthHelperService;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.ConnectionStatus;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;
import org.springframework.web.util.UriComponentsBuilder;

import java.io.IOException;
import java.util.Map;
import java.util.Optional;

/**
 * Connecting a patient's Medicare account (WBS 6.2.39; SRS FR-MCR-01…05).
 *
 * <ol>
 *   <li>The app, signed in, calls {@code GET /v1/api/medicare/connect-url} and opens the URL it
 *       returns. The URL carries a one-time link token, not the JWT.</li>
 *   <li>{@code GET /oauth2/connect} checks the token, keeps it in the session for the round trip,
 *       and hands over to Spring's {@code /oauth2/authorization/medicare}.</li>
 *   <li>Blue Button redirects back to {@code /login/oauth2/code/medicare};
 *       {@link OAuthHelperService} stores the tokens and returns the browser to the app.</li>
 * </ol>
 * The first and last endpoints here run on the stateless JWT chain; {@code /oauth2/connect} runs
 * on the separate session-backed OAuth chain in {@code SecurityConfig}.
 */
@Slf4j
@RestController
public class MedicareConnectionController {

    private final MedicareConnectionService connections;
    private final UserRepository users;
    private final String frontendBaseUrl;

    public MedicareConnectionController(
            final MedicareConnectionService connections,
            final UserRepository users,
            @Value("${frontend.base-url}") final String frontendBaseUrl) {
        this.connections = connections;
        this.users = users;
        this.frontendBaseUrl = frontendBaseUrl;
    }

    /** Step 1. Only a patient links their own Medicare account; nobody links one for them. */
    @GetMapping("/v1/api/{source}/connect-url")
    public ResponseEntity<Map<String, String>> connectUrl(@PathVariable final String source, final Authentication authentication) {
        requireMedicare(source);
        final Long patientId = currentPatientId(authentication)
                .orElseThrow(() -> new AppException(HttpStatus.FORBIDDEN,
                        "Only a patient can connect their own Medicare account"));
        final String linkToken = connections.startLink(patientId);
        final String url = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/oauth2/connect")
                .queryParam("linkToken", linkToken)
                .build()
                .toUriString();
        return ResponseEntity.ok(Map.of("url", url));
    }

    /** Step 2, in the browser. An unknown or expired token goes back to the app, not to Medicare. */
    @GetMapping("/oauth2/connect")
    public void connect(
            @RequestParam(name = "linkToken", required = false) final String linkToken,
            final HttpServletRequest request,
            final HttpServletResponse response) throws IOException {
        if (connections.pendingLink(linkToken).isEmpty()) {
            response.sendRedirect(UriComponentsBuilder.fromUriString(frontendBaseUrl)
                    .queryParam("medicare", MedicareConnectionService.LinkOutcome.LINK_EXPIRED.code())
                    .build()
                    .toUriString());
            return;
        }
        request.getSession(true).setAttribute(OAuthHelperService.LINK_TOKEN_SESSION_ATTRIBUTE, linkToken);
        response.sendRedirect(request.getContextPath() + "/oauth2/authorization/" + MedicareConnectionService.REGISTRATION_ID);
    }

    /**
     * {@code { connected, status, connectedAt }}: always 200, so the app can read a not-linked
     * answer without treating it as an error. A user with no patient record is simply not linked.
     */
    @GetMapping("/v1/api/{source}/status")
    public ResponseEntity<ConnectionStatus> status(@PathVariable final String source, final Authentication authentication) {
        requireMedicare(source);
        return ResponseEntity.ok(currentPatientId(authentication)
                .map(connections::status)
                .orElseGet(() -> new ConnectionStatus(false, "UNLINKED", null)));
    }

    /**
     * Unlinks the signed-in patient's Medicare account (FR-MCR-10/11). The 200 comes back only after
     * the Medicare data has been deleted, as AC-MCR-11-1 requires. A POST: it deletes data, so it
     * must not be reachable by a link or an image tag. Idempotent: unlinking twice is not an error.
     */
    @PostMapping("/v1/api/{source}/disconnect")
    public ResponseEntity<ConnectionStatus> disconnect(@PathVariable final String source, final Authentication authentication) {
        requireMedicare(source);
        final Long patientId = currentPatientId(authentication)
                .orElseThrow(() -> new AppException(HttpStatus.FORBIDDEN,
                        "Only a patient can disconnect their own Medicare account"));
        connections.disconnect(patientId);
        return ResponseEntity.ok(new ConnectionStatus(false, "UNLINKED", null));
    }

    /**
     * The paths follow {@code EhrController}'s {@code /v1/api/{source}/...} shape. Medicare is the
     * only source so far; any other is a 404, as it is there.
     */
    private static void requireMedicare(final String source) {
        if (!MedicareConnectionService.REGISTRATION_ID.equalsIgnoreCase(source)) {
            throw new AppException(HttpStatus.NOT_FOUND, "Unknown source");
        }
    }

    private Optional<Long> currentPatientId(final Authentication authentication) {
        if (authentication == null) {
            return Optional.empty();
        }
        return users.findByEmail(authentication.getName()).flatMap(connections::patientIdFor);
    }

}
