package com.careconnect.controller;

import com.careconnect.service.BluebuttonService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.web.bind.annotation.GetMapping;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;

import java.util.List;


@RestController("/results")
@Slf4j
public class BluebuttonController {

    private final BluebuttonService BBService = new BluebuttonService();
    private final OAuth2AuthorizedClientService oAuth2AuthorizedClientService;

    public BluebuttonController(OAuth2AuthorizedClientService oAuth2AuthorizedClientService) {
        this.oAuth2AuthorizedClientService = oAuth2AuthorizedClientService;
    }

    @GetMapping("/results")
    //@ResponseBody
    public ResponseEntity<String> results(Authentication auth) {
        OAuth2AuthenticationToken oauthToken = (OAuth2AuthenticationToken) auth;

        String registrationId = oauthToken.getAuthorizedClientRegistrationId();

        String principalName = auth.getName();

        OAuth2AuthorizedClient authorizedClient = oAuth2AuthorizedClientService.loadAuthorizedClient(registrationId, principalName);

        if (authorizedClient == null) {
            throw new IllegalStateException("No authorized client found for " + registrationId);
        }
        String accessToken = authorizedClient.getAccessToken().getTokenValue();

        Patient patientout = BBService.requestMedicarePatientInfo(accessToken);
        List<Coverage> coverages = BBService.requestMedicareCoverageInfo(accessToken);
        List<ExplanationOfBenefit> eobs = BBService.requestMedicareEOBInfo(accessToken);


        return ResponseEntity.ok("Got all details!");
    }

}