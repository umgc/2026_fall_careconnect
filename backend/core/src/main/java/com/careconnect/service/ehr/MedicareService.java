package com.careconnect.service.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import ca.uhn.fhir.rest.api.EncodingEnum;
import ca.uhn.fhir.rest.client.api.IGenericClient;
import ca.uhn.fhir.rest.client.interceptor.BearerTokenAuthInterceptor;
import ca.uhn.fhir.rest.param.DateParam;
import ca.uhn.fhir.rest.param.DateRangeParam;
import ca.uhn.fhir.util.BundleUtil;
import com.careconnect.repository.ehr.EhrSourceRepository;
import lombok.Getter;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.instance.model.api.IBaseBundle;
import org.hl7.fhir.instance.model.api.IBaseResource;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import static com.careconnect.service.ehr.EHRService.ctxR4;

@Service
@Slf4j
public class MedicareService {

    private static final String bluebuttonBase = "https://sandbox.bluebutton.cms.gov/v3/fhir/";
    private static final String bluebuttonRevoke = "https://bluebutton.cms.gov/v3/o/revoke";

    @Value("${spring.security.oauth2.client.registration.medicare.client-id}")
    private String clientId;

    @Value("${spring.security.oauth2.client.registration.medicare.client-secret}")
    private String clientSecret;

    @Autowired
    private EhrSourceRepository ehrSourceRepository;

    @Getter
    private Long id;

    public void retrieveId(){
        id = ehrSourceRepository.findByCode("MEDICARE").orElseThrow().getId();
    }


    public void revoke(String patientToken){
        HttpClient client = HttpClient.newHttpClient();
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(bluebuttonRevoke))
                .POST(HttpRequest.BodyPublishers.ofString("token="+patientToken))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Authorization", "Basic " + clientId + ":" + clientSecret).build();
        try {
            client.send(request, HttpResponse.BodyHandlers.discarding());
            // This always returns 200. No real point in checking the result.
        }catch (Exception e){
            log.error("Revoke Failed:{}", e.getMessage());
        }
    }

    public Patient requestMedicarePatientInfo(String patientToken) throws RuntimeException {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        Bundle results = bluebuttonClient.search().forResource(Patient.class).returnBundle(Bundle.class).execute();
        if (results == null) {
            throw new RuntimeException("No Patient Response!");
        }
        if (results.getTotal() == 1) {
            String bundleType = results.getEntry().get(0).getResource().getResourceType().toString();
            if (bundleType.equals("Patient")) {
                return (Patient) results.getEntry().get(0).getResource();
            }

            throw new RuntimeException("Invalid Patient response type: " + bundleType);
        }
        throw new RuntimeException("Invalid Patient response quantity: " + results.getTotal());
    }

    public List<Coverage> requestMedicareCoverageInfo(String patientToken) {
        return requestMedicareCoverageInfo(patientToken, null);
    }

    public List<Coverage> requestMedicareCoverageInfo(String patientToken, Date lastUpdatedDate) throws RuntimeException {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        Bundle results;
        if (lastUpdatedDate != null) {
            results = bluebuttonClient.search().forResource(Coverage.class).lastUpdated(new DateRangeParam(new DateParam().setValue(lastUpdatedDate), null)).returnBundle(Bundle.class).execute();
        } else {
            results = bluebuttonClient.search().forResource(Coverage.class).returnBundle(Bundle.class).execute();
        }
        if (results == null) {
            throw new RuntimeException("No Coverage Response!");
        }
        if (results.getTotal() == 0) {
            return new ArrayList<>();
        }
        String bundleType = results.getEntry().get(0).getResource().getResourceType().toString();
        if (bundleType.equals("Coverage")) {
            List<IBaseResource> totalResults = new ArrayList<>(BundleUtil.toListOfResources(ctxR4, results));
            while (results.getLink(IBaseBundle.LINK_NEXT) != null) {
                results = bluebuttonClient.loadPage().next(results).execute();
                totalResults.addAll(BundleUtil.toListOfResources(ctxR4, results));
            }

            List<Coverage> toReturn = new ArrayList<>();
            for (IBaseResource resource : totalResults) {
                toReturn.add((Coverage) resource);
            }

            return toReturn;
        }
        throw new RuntimeException("Invalid EOB response type: " + bundleType);
    }

    public List<ExplanationOfBenefit> requestMedicareEOBInfo(String patientToken) {
        return requestMedicareEOBInfo(patientToken, null);
    }

    public List<ExplanationOfBenefit> requestMedicareEOBInfo(String patientToken, Date lastUpdatedDate) throws RuntimeException {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        Bundle results;
        if (lastUpdatedDate != null) {
            results = bluebuttonClient.search().forResource(ExplanationOfBenefit.class).lastUpdated(new DateRangeParam(new DateParam().setValue(lastUpdatedDate), null)).returnBundle(Bundle.class).execute();
        } else {
            results = bluebuttonClient.search().forResource(ExplanationOfBenefit.class).returnBundle(Bundle.class).execute();
        }
        if (results == null) {
            throw new RuntimeException("No EOB Response!");
        }
        if (results.getTotal() == 0) {
            return new ArrayList<>();
        }
        String bundleType = results.getEntry().get(0).getResource().getResourceType().toString();
        if (bundleType.equals("ExplanationOfBenefit")) {
            List<IBaseResource> totalResults = new ArrayList<>(BundleUtil.toListOfResources(ctxR4, results));
            while (results.getLink(IBaseBundle.LINK_NEXT) != null) {
                results = bluebuttonClient.loadPage().next(results).execute();
                totalResults.addAll(BundleUtil.toListOfResources(ctxR4, results));
            }

            List<ExplanationOfBenefit> toReturn = new ArrayList<>();
            for (IBaseResource resource : totalResults) {
                toReturn.add((ExplanationOfBenefit) resource);
            }

            return toReturn;
        }
        throw new RuntimeException("Invalid EOB response type: " + bundleType);
    }


}