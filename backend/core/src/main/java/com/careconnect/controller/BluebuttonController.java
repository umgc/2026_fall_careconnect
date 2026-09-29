package com.careconnect.controller;

import com.careconnect.service.FHIRService;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Returns what CMS Blue Button actually sent back for the signed-in beneficiary.
 * <p>
 * Previously this fetched Patient, Coverage and ExplanationOfBenefit and then returned
 * {@code ResponseEntity.ok("")}, discarding all three. A successful retrieval and one that
 * returned nothing were indistinguishable from outside: same 200, same empty body, and
 * {@code FHIRService} logged nothing either. This returns the patient and the resource
 * counts so the call can be observed.
 */
@RestController
@Slf4j
public class BluebuttonController {

    private final FHIRService fhirService;
    private final OAuth2AuthorizedClientService oAuth2AuthorizedClientService;

    @Autowired
    public BluebuttonController(final FHIRService fhirService,
                                final OAuth2AuthorizedClientService oAuth2AuthorizedClientService) {
        this.fhirService = fhirService;
        this.oAuth2AuthorizedClientService = oAuth2AuthorizedClientService;
    }

    @GetMapping("/results")
    public ResponseEntity<String> results(final Authentication auth) {
        if (!(auth instanceof OAuth2AuthenticationToken oauthToken)) {
            log.warn("Blue Button: /results reached without an OAuth2 session (auth={})",
                    auth == null ? "null" : auth.getClass().getSimpleName());
            return ResponseEntity.status(401)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body("{\"error\":\"not signed in through Blue Button\"}");
        }

        final String registrationId = oauthToken.getAuthorizedClientRegistrationId();
        final OAuth2AuthorizedClient authorizedClient =
                oAuth2AuthorizedClientService.loadAuthorizedClient(registrationId, auth.getName());

        if (authorizedClient == null) {
            log.warn("Blue Button: no authorized client for registration '{}'", registrationId);
            return ResponseEntity.status(401)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body("{\"error\":\"no authorized client for " + registrationId + "\"}");
        }

        final String accessToken = authorizedClient.getAccessToken().getTokenValue();
        log.info("Blue Button: retrieving Patient/Coverage/ExplanationOfBenefit for '{}'", registrationId);

        try {
            final Patient patient = fhirService.requestMedicarePatientInfo(accessToken);
            final List<Coverage> coverages = fhirService.requestMedicareCoverageInfo(accessToken);
            final List<ExplanationOfBenefit> eobs = fhirService.requestMedicareEOBInfo(accessToken);

            final int coverageCount = coverages == null ? 0 : coverages.size();
            final int eobCount = eobs == null ? 0 : eobs.size();

            log.info("Blue Button: retrieved patient={} coverages={} eobs={}",
                    patient == null ? "none" : patient.getIdElement().getIdPart(),
                    coverageCount, eobCount);

            final String body = "{\"patient\":" + fhirService.patientToJSON(patient)
                    + ",\"coverageCount\":" + coverageCount
                    + ",\"eobCount\":" + eobCount + "}";

            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(body);
        } catch (RuntimeException e) {
            // Logged here because FHIRService throws bare RuntimeExceptions with no logging of
            // its own; without this the only symptom is a 500 with an empty body.
            log.error("Blue Button retrieval failed: {}", e.getMessage(), e);
            return ResponseEntity.status(502)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body("{\"error\":\"blue button retrieval failed\",\"detail\":\""
                            + String.valueOf(e.getMessage()).replace('"', '\'') + "\"}");
        }
    }
}
