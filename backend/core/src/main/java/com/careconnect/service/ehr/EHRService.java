package com.careconnect.service.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;

@Service
@Slf4j
public class EHRService {
    @Autowired
    private UserRepository userRepository;

    @Autowired
    private EhrPatientCrosswalkRepository ehrPatientCrosswalkRepository;

    public static final FhirContext ctxR4 = FhirContext.forR4();
    private static final IParser parser = ctxR4.newJsonParser().setPrettyPrint(true);
    public String patientToJSON(Patient patient) {
        return parser.encodeResourceToString(patient);
    }
    public String coverageToJSON(Coverage coverage) {
        return parser.encodeResourceToString(coverage);
    }
    public String EOBtoJSON(ExplanationOfBenefit eob) {
        return parser.encodeResourceToString(eob);
    }

    public EhrPatientCrosswalk getCrosswalk(Long id){
        Authentication currentUserAuth = SecurityContextHolder.getContext().getAuthentication();
        log.info(currentUserAuth.getName());
        User currentUser = userRepository.findByEmail(currentUserAuth.getName()).orElseThrow();
        return ehrPatientCrosswalkRepository.findByPatientIdAndSourceId(currentUser.getId(), id).orElseThrow();
    }

}
