package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.service.FHIRService;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.web.servlet.error.ErrorController;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;


@RestController("/results")
@Slf4j
public class BluebuttonController {

    private final FHIRService fhirService = new FHIRService();

    @Autowired
    private OAuth2AuthorizedClientService oAuth2AuthorizedClientService;

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

        Patient patientout = fhirService.requestMedicarePatientInfo(accessToken);
        List<Coverage> coverages = fhirService.requestMedicareCoverageInfo(accessToken);
        List<ExplanationOfBenefit> eobs = fhirService.requestMedicareEOBInfo(accessToken);

    return ResponseEntity.ok("");
    }

}