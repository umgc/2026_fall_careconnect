package com.example.demo;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import ca.uhn.fhir.rest.api.EncodingEnum;
import ca.uhn.fhir.rest.client.api.IGenericClient;
import ca.uhn.fhir.rest.client.interceptor.BearerTokenAuthInterceptor;
import ca.uhn.fhir.rest.param.DateParam;
import ca.uhn.fhir.rest.param.DateRangeParam;
import ca.uhn.fhir.util.BundleUtil;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.instance.model.api.IBaseBundle;
import org.hl7.fhir.instance.model.api.IBaseResource;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

@Service
@Slf4j
public class FHIRService {

    private static final FhirContext ctxR4 = FhirContext.forR4();
    private static final IParser parser = ctxR4.newJsonParser().setPrettyPrint(true);

    private static final String bluebuttonBase = "https://sandbox.bluebutton.cms.gov/v2/fhir/";

    public Patient requestMedicarePatientInfo(String patientToken) throws RuntimeException {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        Bundle results = bluebuttonClient.search().forResource(Patient.class).returnBundle(Bundle.class).execute();
        if (results == null) {
            throw new RuntimeException("No Patient Response!");
        }
        if (results.getTotal() == 1) {
            String bundleType = results.getEntry().getFirst().getResource().getResourceType().toString();
            if (bundleType.equals("Patient")) {
                return (Patient) results.getEntry().getFirst().getResource();
            }

            throw new RuntimeException("Invalid Patient response type: " + bundleType);
        }
        throw new RuntimeException("Invalid Patient response quantity: " + results.getTotal());
    }

    public String patientToJSON(Patient patient) {
        return parser.encodeResourceToString(patient);
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
        String bundleType = results.getEntry().getFirst().getResource().getResourceType().toString();
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

    public String coverageToJSON(Coverage coverage) {
        return parser.encodeResourceToString(coverage);
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
        String bundleType = results.getEntry().getFirst().getResource().getResourceType().toString();
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

    public String EOBtoJSON(ExplanationOfBenefit eob) {
        return parser.encodeResourceToString(eob);
    }


}