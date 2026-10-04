package com.careconnect.service.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.PatientRepository;
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

import java.util.Optional;

@Service
@Slf4j
public class EhrService {
    @Autowired
    private UserRepository userRepository;

    @Autowired
    private EhrPatientCrosswalkRepository ehrPatientCrosswalkRepository;

    @Autowired
    private PatientRepository patientRepository;

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

    /**
     * The signed-in patient's <em>linked</em> crosswalk row for this source. Empty for a user with no
     * patient record, no row, or a link that is still pending (no token yet).
     * <p>
     * Keyed by {@code patient.id}: the crosswalk's {@code patient_id} is a foreign key to
     * {@code patient}, and a user id is a different number for most accounts.
     */
    public Optional<EhrPatientCrosswalk> getCrosswalk(Long id){
        Authentication currentUserAuth = SecurityContextHolder.getContext().getAuthentication();
        if (currentUserAuth == null) {
            return Optional.empty();
        }
        return userRepository.findByEmail(currentUserAuth.getName())
                .flatMap(user -> patientRepository.findByUserId(user.getId()))
                .flatMap(patient -> ehrPatientCrosswalkRepository.findByPatientIdAndSourceId(patient.getId(), id))
                .filter(EhrPatientCrosswalk::isLinked);
    }

}
