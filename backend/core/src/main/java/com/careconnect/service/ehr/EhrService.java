package com.careconnect.service.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import ca.uhn.fhir.rest.client.apache.ApacheRestfulClientFactory;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrCoverageRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrVisitRecord;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EhrCoverageRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrVisitRecordRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import lombok.extern.slf4j.Slf4j;
import org.apache.http.impl.client.HttpClientBuilder;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.Optional;

@Service
@Slf4j
public class EhrService {
    @Autowired
    private UserRepository userRepository;

    @Autowired
    private EhrPatientCrosswalkRepository ehrPatientCrosswalkRepository;

    @Autowired
    private EhrVisitRecordRepository ehrVisitRecordRepository;

    @Autowired
    private EhrCoverageRecordRepository ehrCoverageRecordRepository;

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private CaregiverPatientLinkRepository caregiverPatientLinkRepository;

    @Autowired
    private FamilyMemberLinkRepository familyMemberLinkRepository;

    private final ObjectMapper objectMapper = new ObjectMapper();

    public static final FhirContext ctxR4 = blueButtonContext();
    private static final IParser parser = ctxR4.newJsonParser().setPrettyPrint(true);

    /**
     * The R4 context, with Apache HttpClient's own retries turned off. {@link BlueButtonRetryPolicy}
     * owns retrying; HttpClient would otherwise resend a dropped request up to 3 more times inside
     * each attempt, 12 requests where NFR-DEG-02 allows 3 (DEF-MCR-06, first fixed on #223).
     * HAPI's timeouts and connection pool stay as they are.
     */
    private static FhirContext blueButtonContext() {
        final FhirContext ctx = FhirContext.forR4();
        ctx.setRestfulClientFactory(new ApacheRestfulClientFactory(ctx) {
            @Override
            protected HttpClientBuilder getHttpClientBuilder() {
                return super.getHttpClientBuilder().disableAutomaticRetries();
            }
        });
        return ctx;
    }
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

    public void updateCoverageRepository(EhrCoverageRecord coverage) {
        // Either update an existing coverage by replacing the id or add this new one to the mix.
        Optional<EhrCoverageRecord> check = ehrCoverageRecordRepository.findByPatientIdAndSourceIdAndExternalCoverageId(coverage.getPatientId(), coverage.getSourceId(), coverage.getExternalCoverageId());
        check.ifPresent(ehrCoverageRecord -> coverage.setId(ehrCoverageRecord.getId()));
        ehrCoverageRecordRepository.save(coverage);
    }

    public void updateVisitRepository(EhrVisitRecord visit) {
        // Either update an existing visit record by replacing the id or add this new one to the mix.
        Optional<EhrVisitRecord> check = ehrVisitRecordRepository.findByPatientIdAndSourceIdAndExternalVisitId(visit.getPatientId(), visit.getSourceId(), visit.getExternalVisitId());
        check.ifPresent(ehrVisitRecord -> visit.setId(ehrVisitRecord.getId()));
        ehrVisitRecordRepository.save(visit);
    }

    /** The signed-in user's id, for the audit log's acting user. Empty when nobody is signed in. */
    public Optional<Long> currentUserId() {
        Authentication currentUserAuth = SecurityContextHolder.getContext().getAuthentication();
        if (currentUserAuth == null) {
            return Optional.empty();
        }
        return userRepository.findByEmail(currentUserAuth.getName()).map(user -> user.getId());
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

    /**
     * Whether the signed-in user may read this patient's Medicare data (FR-MCR-16, FR-MCR-17, NFR-SEC-05):
     * the patient themself, or a caregiver or family member with an active, unexpired link to them.
     * Anyone else is refused, including an admin and a patient asking for another patient.
     *
     * @param patientId the {@code patient.id} asked for, not a user id
     */
    public boolean canReadMedicareFor(Long patientId) {
        Authentication currentUserAuth = SecurityContextHolder.getContext().getAuthentication();
        if (currentUserAuth == null || patientId == null) {
            return false;
        }
        Optional<User> caller = userRepository.findByEmail(currentUserAuth.getName());
        Optional<User> patientUser = patientRepository.findById(patientId).map(com.careconnect.model.Patient::getUser);
        if (caller.isEmpty() || patientUser.isEmpty() || caller.get().getRole() == null) {
            return false;
        }
        User user = caller.get();
        LocalDateTime now = LocalDateTime.now();
        return switch (user.getRole()) {
            case PATIENT -> user.getId().equals(patientUser.get().getId());
            case CAREGIVER -> caregiverPatientLinkRepository.existsActiveNonExpiredLinkByUserIds(
                    user.getId(), patientUser.get().getId(), now);
            case FAMILY_MEMBER -> familyMemberLinkRepository.existsActiveNonExpiredLink(user, patientUser.get(), now);
            default -> false;
        };
    }

    /**
     * That patient's <em>linked</em> crosswalk row for this source, for a caller {@link #canReadMedicareFor}
     * has already allowed. Empty when the patient has not connected the source or the link is still pending.
     */
    public Optional<EhrPatientCrosswalk> getCrosswalkForPatient(Long patientId, Long sourceId) {
        return ehrPatientCrosswalkRepository.findByPatientIdAndSourceId(patientId, sourceId)
                .filter(EhrPatientCrosswalk::isLinked);
    }

}
