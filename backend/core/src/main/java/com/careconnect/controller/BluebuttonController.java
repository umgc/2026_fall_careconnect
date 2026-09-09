package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import org.springframework.boot.web.servlet.error.ErrorController;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;

@RestController("/results")
@Slf4j
public class BluebuttonController {

    private final FHIRService fhirService = new FHIRService();
    private final OAuth2AuthorizedClientService oAuth2AuthorizedClientService;

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

    }

}