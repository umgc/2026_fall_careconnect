package com.careconnect.controller.ehr;

import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.MedicareNotConnectedException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

/**
 * Turns a lapsed or rejected Medicare link into ERR-MCR-05 for the Medicare read endpoints, instead
 * of the 500 the app-wide catch-all in {@code GlobalExceptionHandler} would give (FR-MCR-09).
 * <p>
 * Answers <b>409</b>, not 401. A 401 from our API tells the app its own CareConnect session has
 * expired and signs the user out; here the user is signed in fine and only the Medicare link needs
 * renewing. The body says so, with {@code connected: false} so the tile can offer to connect again.
 * <p>
 * Ordered first because Spring uses the first advice that has any matching handler, and
 * {@code GlobalExceptionHandler}'s {@code Exception} handler matches everything.
 * <p>
 * Its collaborators are looked up lazily: every {@code @WebMvcTest} slice loads all advice beans,
 * and those slices have no Medicare service or repositories to inject.
 */
@Slf4j
@Order(Ordered.HIGHEST_PRECEDENCE)
@RestControllerAdvice(assignableTypes = EhrController.class)
public class MedicareErrorAdvice {

    private final ObjectProvider<MedicareConnectionService> connections;
    private final ObjectProvider<UserRepository> users;

    public MedicareErrorAdvice(
            final ObjectProvider<MedicareConnectionService> connections,
            final ObjectProvider<UserRepository> users) {
        this.connections = connections;
        this.users = users;
    }

    /** No working link: never linked, unlinked, or the refresh was rejected. */
    @ExceptionHandler(MedicareNotConnectedException.class)
    public ResponseEntity<Map<String, Object>> notConnected(final MedicareNotConnectedException e) {
        return errMcr05();
    }

    /**
     * Blue Button answered 401 to a data request: the token is no good. Mark the link Unlinked so no
     * further call is made with it (AC-MCR-09-2), then answer ERR-MCR-05.
     */
    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<Map<String, Object>> tokenRejected(final AuthenticationException e) {
        final Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        final MedicareConnectionService service = connections.getIfAvailable();
        final UserRepository userRepository = users.getIfAvailable();
        if (authentication != null && service != null && userRepository != null) {
            userRepository.findByEmail(authentication.getName())
                    .flatMap(service::patientIdFor)
                    .ifPresent(service::markTokenRejected);
        }
        log.info("Blue Button rejected a stored Medicare token; link set to Unlinked (FR-MCR-09)");
        return errMcr05();
    }

    private static ResponseEntity<Map<String, Object>> errMcr05() {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                "error", "ERR-MCR-05",
                "message", MedicareConnectionService.ERR_MCR_05_MESSAGE,
                "connected", false));
    }
}
