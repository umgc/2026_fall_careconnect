package com.careconnect.controller;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.PkceUtil;
import com.careconnect.service.ehr.CernerAuthStateStore;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.CernerPatientLinkService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

/** Provisional Oracle Health connection lifecycle pending unified OpenAPI approval. */
@RestController
@RequestMapping("/api/oracle-health")
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class CernerOAuthController {

    private final CernerOAuthService oauth;
    private final CernerAuthStateStore states;
    private final CernerPatientLinkService links;
    private final SecurityUtil security;
    private final PatientRepository patients;
    private final CernerProperties config;

    @GetMapping("/authorize")
    public ResponseEntity<Map<String, String>> authorize(
            @RequestParam(required = false) final String launch,
            @RequestParam(required = false) final String returnMode) {
        User user = security.resolveCurrentUser();
        if (user == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (patients.findByUserId(user.getId()).isEmpty()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        String verifier = PkceUtil.newCodeVerifier();
        String state = states.issue(user.getId(), verifier, returnMode);
        return ResponseEntity.ok(Map.of(
                "authUrl", oauth.buildAuthorizeUrl(state, PkceUtil.s256Challenge(verifier), launch)));
    }

    @GetMapping("/callback")
    public ResponseEntity<Void> callback(
            @RequestParam(required = false) final String code,
            @RequestParam(required = false) final String state,
            @RequestParam(required = false) final String error) {
        CernerAuthStateStore.Entry stored = states.consume(state);
        String returnUrl = returnUrl(stored);
        if (stored == null || error != null || code == null || code.isBlank()) {
            return redirect(returnUrl + "?status=error");
        }
        try {
            EhrCredential credential = oauth.exchangeAndStore(
                    stored.userId(), code, stored.verifier());
            links.link(stored.userId(), credential.getPatientFhirId());
            return redirect(returnUrl + "?status=ok");
        } catch (RuntimeException exception) {
            oauth.disconnect(stored.userId());
            return redirect(returnUrl + "?status=error");
        }
    }

    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> status() {
        User user = security.resolveCurrentUser();
        if (user == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        Optional<EhrCredential> credential = oauth.findCredential(user.getId());
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("source", CernerProperties.SOURCE_ORACLE_HEALTH);
        body.put("connected", credential
                .map(value -> value.getStatus() == EhrCredential.Status.ACTIVE)
                .orElse(false));
        credential.ifPresent(value -> body.put("status", value.getStatus().name()));
        return ResponseEntity.ok(body);
    }

    @PostMapping("/disconnect")
    public ResponseEntity<Map<String, Object>> disconnect() {
        User user = security.resolveCurrentUser();
        if (user == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        oauth.disconnect(user.getId());
        return ResponseEntity.ok(Map.of(
                "source", CernerProperties.SOURCE_ORACLE_HEALTH,
                "connected", false));
    }

    private String returnUrl(final CernerAuthStateStore.Entry state) {
        return state != null && "web".equalsIgnoreCase(state.returnMode())
                ? config.getWebReturnUrl() : config.getAppReturnDeepLink();
    }

    private static ResponseEntity<Void> redirect(final String location) {
        return ResponseEntity.status(HttpStatus.FOUND).location(URI.create(location)).build();
    }
}
