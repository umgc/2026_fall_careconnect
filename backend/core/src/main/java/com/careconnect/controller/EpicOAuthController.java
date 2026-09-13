package com.careconnect.controller;

import com.careconnect.config.EpicProperties;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.security.PkceUtil;
import com.careconnect.service.ConsentService;
import com.careconnect.service.ehr.EpicAuthStateStore;
import com.careconnect.service.ehr.EpicOAuthService;
import com.careconnect.service.ehr.EpicSyncService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Epic SMART-on-FHIR connect surface (Phase 0 / doc 1_8).
 *
 * <ul>
 *   <li>{@code GET /api/epic/authorize} — authenticated; returns the Epic authorize URL.</li>
 *   <li>{@code GET /api/epic/callback} — unauthenticated; recovers the user from the signed,
 *       single-use state, exchanges the code, records consent, triggers sync, deep-links back.</li>
 *   <li>{@code GET /api/epic/status} / {@code POST /api/epic/disconnect} — connection lifecycle.</li>
 * </ul>
 *
 * Gated on {@code careconnect.epic.enabled}.
 */
@Slf4j
@RestController
@RequestMapping("/api/epic")
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.epic.enabled", havingValue = "true")
public class EpicOAuthController {

    private final EpicOAuthService epic;
    private final EpicAuthStateStore stateStore;
    private final SecurityUtil securityUtil;
    private final ConsentService consentService;
    private final EpicSyncService syncService;
    private final EhrResourceRepository resourceRepo;
    private final ObjectMapper objectMapper;
    private final EpicProperties cfg;

    @GetMapping("/authorize")
    public ResponseEntity<Map<String, String>> authorize(
            @RequestParam(required = false) String returnMode) {
        User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        String verifier = PkceUtil.newCodeVerifier();
        String challenge = PkceUtil.s256Challenge(verifier);
        // returnMode ("web") is remembered server-side against the state so the callback can send
        // the browser back to the web app; absent/other => the mobile deep link (unchanged).
        String state = stateStore.issue(me.getId(), verifier, returnMode);
        String url = epic.buildAuthorizeUrl(state, challenge);
        return ResponseEntity.ok(Map.of("authUrl", url));
    }

    @GetMapping("/callback")
    public ResponseEntity<Void> callback(
            @RequestParam(required = false) String code,
            @RequestParam(required = false) String state,
            @RequestParam(required = false) String error) {
        // Consume the state first so we know the return target (web URL vs mobile deep link),
        // then use that same base for both the error and success redirects.
        EpicAuthStateStore.Entry st = stateStore.consume(state);
        String returnBase = returnBaseFor(st);
        if (error != null && !error.isBlank()) {
            return redirect(returnBase + "?status=error");
        }
        if (st == null || code == null || code.isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
        }
        try {
            epic.exchangeAndStore(st.userId(), code, st.codeVerifier());
            consentService.recordEhrImportConsent(st.userId());
            syncService.enqueueInitialSync(st.userId());
            return redirect(returnBase + "?status=ok");
        } catch (RuntimeException ex) {
            // Log the full exception (message + stack + cause chain) so the actual failure is
            // diagnosable — the token endpoint's HTTP error body is already logged by
            // EpicOAuthService.postForToken; this covers every other cause (TLS, parsing, persistence).
            log.warn("Epic callback failed for user {}", st.userId(), ex);
            return redirect(returnBase + "?status=error");
        }
    }

    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> status() {
        User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        Optional<EhrCredential> cred = epic.findCredential(me.getId());
        Map<String, Object> body = new HashMap<>();
        body.put("connected", cred.map(c -> c.getStatus() == EhrCredential.Status.ACTIVE).orElse(false));
        cred.ifPresent(c -> {
            body.put("status", c.getStatus().name());
            body.put("connectedAt", c.getCreatedAt() != null ? c.getCreatedAt().toString() : null);
        });
        return ResponseEntity.ok(body);
    }

    /**
     * DIAGNOSTIC: re-run the initial Epic sync synchronously for the current user and return the
     * result (or the underlying error, including Epic's HTTP status and response body). The normal
     * sync runs async on connect and only records "ERROR" in the audit; this surfaces the cause.
     */
    @GetMapping("/resync")
    public ResponseEntity<Map<String, Object>> resync() {
        User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        Map<String, Object> out = new HashMap<>();
        try {
            int stored = syncService.syncNow(me.getId());
            out.put("stored", stored);
            out.put("ok", true);
            return ResponseEntity.ok(out);
        } catch (Exception ex) {
            out.put("ok", false);
            out.put("error", ex.getClass().getName());
            out.put("message", ex.getMessage());
            Throwable cause = ex;
            while (cause.getCause() != null && cause.getCause() != cause) {
                cause = cause.getCause();
            }
            out.put("rootCause", cause.getClass().getName() + ": " + cause.getMessage());
            if (cause instanceof org.springframework.web.client.RestClientResponseException rce) {
                out.put("httpStatus", rce.getStatusCode().value());
                out.put("responseBody", rce.getResponseBodyAsString());
            }
            return ResponseEntity.ok(out);
        }
    }

    /**
     * Read one mirrored Epic resource for the current user (Epic Phase 2). Scoped to the caller's
     * own {@code ehr_resource} rows (userId from the JWT, never a client-supplied id) so it cannot
     * be used to read another patient's data. Backs the Epic citation detail page.
     */
    @GetMapping("/resource/{type}/{id}")
    public ResponseEntity<Map<String, Object>> resource(
            @PathVariable("type") String type,
            @PathVariable("id") String id) {
        User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        Optional<EhrResource> found = resourceRepo
                .findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
                        me.getId(), EpicProperties.SOURCE_EPIC, type, id);
        if (found.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        EhrResource r = found.get();
        Map<String, Object> body = new HashMap<>();
        body.put("resourceType", r.getResourceType());
        body.put("resourceId", r.getResourceFhirId());
        body.put("title", r.getTitle());
        body.put("status", r.getStatusValue());
        body.put("occurredAt", r.getOccurredAt());
        body.put("lastSyncedAt", r.getLastSyncedAt() != null ? r.getLastSyncedAt().toString() : null);
        body.put("resource", parsePayload(r.getPayloadJson()));
        return ResponseEntity.ok(body);
    }

    private JsonNode parsePayload(String json) {
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            return objectMapper.readTree(json);
        } catch (Exception ignored) {
            return null;
        }
    }

    @PostMapping("/disconnect")
    public ResponseEntity<Map<String, Object>> disconnect() {
        User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        epic.disconnect(me.getId());
        consentService.revokeEhrImportConsent(me.getId());
        int removed = syncService.removeEpicData(me.getId());
        return ResponseEntity.ok(Map.of("disconnected", true, "chunksRemoved", removed));
    }

    /**
     * Pick the post-callback return target: the web app URL when the flow was started with
     * {@code returnMode=web}, otherwise the mobile deep link. A missing/expired state (e.g. an Epic
     * error with no recoverable state) falls back to the deep link.
     */
    private String returnBaseFor(EpicAuthStateStore.Entry st) {
        boolean web = st != null && "web".equalsIgnoreCase(st.returnMode());
        return web ? cfg.getWebReturnUrl() : cfg.getAppReturnDeepLink();
    }

    private ResponseEntity<Void> redirect(String location) {
        return ResponseEntity.status(HttpStatus.FOUND).location(URI.create(location)).build();
    }
}
