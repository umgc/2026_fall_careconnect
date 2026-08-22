package com.careconnect.service;

import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.PatientRepository;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Date;
import java.util.ArrayList;
import java.util.stream.Collectors;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.util.BundleUtil;
import ca.uhn.fhir.rest.param.DateParam;
import ca.uhn.fhir.rest.param.DateRangeParam;
import ca.uhn.fhir.rest.annotation.Search;
import ca.uhn.fhir.rest.client.api.IGenericClient;
import ca.uhn.fhir.rest.api.EncodingEnum;
import ca.uhn.fhir.rest.client.interceptor.BearerTokenAuthInterceptor;

import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.instance.model.api.IBaseBundle;
import org.hl7.fhir.instance.model.api.IBaseResource;

public class FHIRService {

    private final FhirContext ctxR4 = FhirContext.forR4();

    private final String bluebuttonBase = "https://sandbox.bluebutton.cms.gov/v2/fhir/";

    public Patient requestMedicarePatientInfo(String patientToken) throws Exception {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        Bundle results = bluebuttonClient.search().forResource(Patient.class).returnBundle(Bundle.class).execute();
        if (results.fhirType().equals("Patient") && results.getTotal() == 1) {
            return (Patient) results.getEntry().get(0).getResource();
        }
        throw new Exception("Invalid response!");
    }

    public Coverage requestMedicareCoverageInfo(String patientToken) throws Exception {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        Bundle results = bluebuttonClient.search().forResource(Coverage.class).returnBundle(Bundle.class).execute();
        if (results.fhirType().equals("Coverage") && results.getTotal() == 1) {
            return (Coverage) results.getEntry().get(0).getResource();
        }
        throw new Exception("Invalid response!");
    }


    public List<ExplanationOfBenefit> requestMedicareEOBInfo(String patientToken, Date lastUpdatedDate) {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        Bundle results;
        if (lastUpdatedDate != null) {
            results = bluebuttonClient.search().forResource(ExplanationOfBenefit.class)
                    .lastUpdated(new DateRangeParam(new DateParam().setValue(lastUpdatedDate), null))
                    .returnBundle(Bundle.class).execute();
        } else {
            results = bluebuttonClient.search().forResource(ExplanationOfBenefit.class).returnBundle(Bundle.class).execute();
        }

        if (results.fhirType().equals("ExplanationOfBenefit") && results.getTotal() >= 0) {
            List<IBaseResource> totalResults = new ArrayList<>();
            totalResults.addAll(BundleUtil.toListOfResources(ctxR4, results));
            while(results.getLink(IBaseBundle.LINK_NEXT) != null){
                results = bluebuttonClient.loadPage().next(results).execute();
                totalResults.addAll(BundleUtil.toListOfResources(ctxR4, results));
            }

            List<ExplanationOfBenefit> toReturn = new ArrayList<>();
            for(IBaseResource resource : totalResults){
                toReturn.add((ExplanationOfBenefit) resource);
            }

            return toReturn;
        }
        return new ArrayList<>();
    }

}