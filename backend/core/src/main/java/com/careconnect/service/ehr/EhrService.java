package com.careconnect.service.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
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

    private ObjectMapper objectMapper = new ObjectMapper();

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
    public Patient jsonToPatient(String patient){return parser.parseResource(Patient.class, patient);}
    public Coverage jsonToCoverage(String coverage){return parser.parseResource(Coverage.class, coverage);}
    public ExplanationOfBenefit jsonToEOB(String eob){return parser.parseResource(ExplanationOfBenefit.class, eob);}

    public JsonNode patientToNode(Patient patient) throws JsonProcessingException {return objectMapper.readTree(patientToJSON(patient));}
    public JsonNode coverageToNode(Coverage coverage) throws JsonProcessingException {return objectMapper.readTree(coverageToJSON(coverage));}
    public JsonNode eobToNode(ExplanationOfBenefit eob) throws JsonProcessingException {return objectMapper.readTree(EOBtoJSON(eob));}

    public EhrRawPayload patientToRawPayload(Patient patient, Long patientId, OffsetDateTime retrievedAt, Long sourceId) {
        EhrRawPayload toreturn = new EhrRawPayload();
        toreturn.setPatientId(patientId);
        toreturn.setPayload(patientToJSON(patient));
        toreturn.setSourceId(sourceId);
        toreturn.setResourceType("SourceIdentity");
        toreturn.setRetrievedAt(retrievedAt);
        toreturn.setExternalResourceId(patient.getId());
        return toreturn;
    }

    public EhrRawPayload coverageToRawPayload(Coverage coverage, Long patientId, OffsetDateTime retrievedAt, Long sourceId) {
        EhrRawPayload toreturn = new EhrRawPayload();
        toreturn.setPatientId(patientId);
        toreturn.setPayload(coverageToJSON(coverage));
        toreturn.setSourceId(sourceId);
        toreturn.setResourceType("CoverageRecord");
        toreturn.setRetrievedAt(retrievedAt);
        toreturn.setExternalResourceId(coverage.getId());
        return toreturn;
    }

    public EhrRawPayload eobToRawPayload(ExplanationOfBenefit eob, Long patientId, OffsetDateTime retrievedAt, Long sourceId) {
        EhrRawPayload toreturn = new EhrRawPayload();
        toreturn.setPatientId(patientId);
        toreturn.setPayload(EOBtoJSON(eob));
        toreturn.setSourceId(sourceId);
        toreturn.setResourceType("VisitRecord");
        toreturn.setRetrievedAt(retrievedAt);
        toreturn.setExternalResourceId(eob.getId());
        return toreturn;
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
