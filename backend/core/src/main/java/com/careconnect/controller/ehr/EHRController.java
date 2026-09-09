package com.careconnect.controller.ehr;
import com.careconnect.model.User;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.EHRCoverageRepository;
import com.careconnect.repository.ehr.EHRIdentityRepository;
import com.careconnect.repository.ehr.EHRVisitRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.service.ehr.EHRService;
import com.careconnect.service.ehr.MedicareService;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.List;

@RestController
@Slf4j
public class EHRController{

    @Autowired
    private MedicareService medicareService;

    @Autowired
    private EHRService ehrService;

    @Autowired
    private EHRCoverageRepository ehrCoverageRepository;

    @Autowired
    private EHRIdentityRepository ehrIdentityRepository;

    @Autowired
    private EHRVisitRecordRepository ehrVisitRecordRepository;




    @GetMapping("/v1/api/identity")
    public ResponseEntity<EHRIdentity> fetchIdentity(String source){

        if(source.equals("medicare")){
            Long medicareId = medicareService.getId();
            EhrPatientCrosswalk crosswalk = ehrService.getCrosswalk(medicareId);
            List<EHRIdentity> identities =
                    ehrIdentityRepository.findByClientIdAndSourceIdOrderByLastUpdatedDesc(
                            crosswalk.getPatientId(), medicareId);

            EHRIdentity toreturn;
            if(identities.isEmpty() || ChronoUnit.DAYS.between(identities.get(0).getLastUpdated(), LocalDateTime.now()) < 1){
                Patient results = medicareService.requestMedicarePatientInfo(crosswalk.getToken());
                // Remove the old copy
                ehrIdentityRepository.deleteByClientIdandSourceId(crosswalk.getId(), medicareId);
                // Add the new one.
                toreturn = ehrIdentityRepository.save(new EHRIdentity(crosswalk.getPatientId(), results, LocalDateTime.now(),
                        medicareId));
            }else{
                toreturn = identities.get(0);
            }

            return ResponseEntity.ok(toreturn);
        }

        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/coverages")
    public ResponseEntity<List<EHRCoverage>> fetchCoverage(String source){

        if(source.equals("medicare")) {
            Long medicareId = medicareService.getId();
            EhrPatientCrosswalk crosswalk = ehrService.getCrosswalk(medicareId);
            List<EHRCoverage> coverages =
                    ehrCoverageRepository.findByClientIdAndSourceIdOrderByLastUpdatedDesc(
                            crosswalk.getPatientId(), medicareId);
            if (coverages.isEmpty()){
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(crosswalk.getToken());
                for(Coverage item: results){
                    coverages.add(ehrCoverageRepository.save(new EHRCoverage(crosswalk.getPatientId(), item, LocalDateTime.now(),
                            medicareId)));
                }

            }else if(ChronoUnit.DAYS.between(coverages.get(0).getLastUpdated(), LocalDateTime.now()) < 1) {
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(crosswalk.getToken(),
                        Date.from(coverages.get(0).getLastUpdated().atZone(ZoneId.systemDefault()).toInstant()));
                for(Coverage item: results){
                    // Delete any old copies that might be the same resource
                    ehrCoverageRepository.deleteBySourceIdAndIdentifier(medicareId, item.getId());

                    // Add a new copy of the resource
                    coverages.add(ehrCoverageRepository.save(new EHRCoverage(crosswalk.getPatientId(), item, LocalDateTime.now(),
                            medicareId)));
                }
            }

            return ResponseEntity.ok(coverages);
        }
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/visits")
    public ResponseEntity<List<EHRVisitRecord>> fetchVisits(String source){
        if(source.equals("medicare")){
            Long medicareId = medicareService.getId();
            EhrPatientCrosswalk crosswalk = ehrService.getCrosswalk(medicareId);
            List<EHRVisitRecord> visits =
                    ehrVisitRecordRepository.findByClientIdAndSourceIdOrderByLastUpdatedDesc(
                            crosswalk.getPatientId(), medicareId);
            if (visits.isEmpty()){
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(crosswalk.getToken());
                for(ExplanationOfBenefit item: results){

                    visits.add(ehrVisitRecordRepository.save(new EHRVisitRecord(crosswalk.getPatientId(), item, LocalDateTime.now(),
                            medicareId)));
                }

            }else if(ChronoUnit.DAYS.between(visits.get(0).getLastUpdated(), LocalDateTime.now()) < 1) {
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(crosswalk.getToken(),
                        Date.from(visits.get(0).getLastUpdated().atZone(ZoneId.systemDefault()).toInstant()));
                for(ExplanationOfBenefit item: results){
                    // Delete any old copies of the same resource
                    ehrVisitRecordRepository.deleteBySourceIdAndIdentifier(medicareId, item.getId());

                    // Add a new copy of the resource
                    visits.add(ehrVisitRecordRepository.save(new EHRVisitRecord(crosswalk.getPatientId(), item, LocalDateTime.now(),
                            medicareId)));
                }
            }

            return ResponseEntity.ok(visits);
        }
        return ResponseEntity.notFound().build();
    }

    @PostMapping("/v1/api/revoke")
    public ResponseEntity<String> revokeAccess(String source){
        if(source.equals("medicare")) {
            Long medicareId = medicareService.getId();
            EhrPatientCrosswalk crosswalk = ehrService.getCrosswalk(medicareId);
            medicareService.revoke(crosswalk.getToken());
            return ResponseEntity.ok("Revoked!");
        }
        return ResponseEntity.notFound().build();
    }


}