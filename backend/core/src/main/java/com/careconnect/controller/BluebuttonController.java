package com.careconnect.controller;

import com.careconnect.service.BluebuttonService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.security.oauth2.client.annotation.RegisteredOAuth2AuthorizedClient;
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

    @GetMapping("/results")
    //@ResponseBody
    public ResponseEntity<String> results(
            @RegisteredOAuth2AuthorizedClient("bluebutton")
            OAuth2AuthorizedClient authorizedClient) {

        String accessToken = authorizedClient.getAccessToken().getTokenValue();

        Patient patientout = BBService.requestMedicarePatientInfo(accessToken);
        List<Coverage> coverages = BBService.requestMedicareCoverageInfo(accessToken);
        List<ExplanationOfBenefit> eobs = BBService.requestMedicareEOBInfo(accessToken);


        return ResponseEntity.ok("Got all details!");
    }

}