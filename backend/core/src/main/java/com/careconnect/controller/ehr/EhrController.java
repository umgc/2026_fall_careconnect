package com.careconnect.controller.ehr;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.ehr.*;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareService;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.List;
import java.util.Optional;

@RestController
@Slf4j
public class EhrController{

    @Autowired
    private MedicareService medicareService;

    @Autowired
    private EhrService ehrService;

    @Autowired
    private EhrCoverageRecordRepository ehrCoverageRepository;

    @Autowired
    private EhrSourceIdentityRepository ehrIdentityRepository;

    @Autowired
    private EHRVisitRecordRepository ehrVisitRecordRepository;




    @GetMapping("/v1/api/identity")
    public ResponseEntity<EhrSourceIdentity> fetchIdentity(String source){

        if(source.equals("medicare")){
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }
            EhrPatientCrosswalk crosswalk = ehrService.getCrosswalk(medicareId);
            Optional<EhrSourceIdentity> identities =
                    ehrIdentityRepository.findByPatientIdAndSourceId(
                            crosswalk.getPatientId(), medicareId);

            EhrSourceIdentity toreturn;
            if(identities.isEmpty() || ChronoUnit.DAYS.between(identities.orElseThrow().getSourceUpdatedAt(), LocalDateTime.now()) < 1){
                Patient results = medicareService.requestMedicarePatientInfo(crosswalk.getToken());
                // Remove the old copy
                if(identities.isPresent()){
                    ehrIdentityRepository.deleteById(identities.orElseThrow().getId());
                }
                // Add the new one.
                toreturn = ehrIdentityRepository.save(new EhrSourceIdentity(crosswalk.getPatientId(), results,
                        medicareId));
            }else{
                toreturn = identities.orElseThrow();
            }

            return ResponseEntity.ok(toreturn);
        }

        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/coverages")
    public ResponseEntity<List<EhrCoverageRecord>> fetchCoverage(String source){

        if(source.equals("medicare")) {
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }
            EhrPatientCrosswalk crosswalk = ehrService.getCrosswalk(medicareId);
            List<EhrCoverageRecord> coverages =
                    ehrCoverageRepository.findByPatientIdAndSourceId(
                            crosswalk.getPatientId(), medicareId);
            if (coverages.isEmpty()){
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(crosswalk.getToken());
                for(Coverage item: results){
                    coverages.add(ehrCoverageRepository.save(new EhrCoverageRecord(crosswalk.getPatientId(), item, medicareId)));
                }

            }else if(ChronoUnit.DAYS.between(coverages.get(0).getSourceUpdatedAt(), LocalDateTime.now()) < 1) {
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(crosswalk.getToken(),
                        Date.from(coverages.get(0).getSourceUpdatedAt().atZone(ZoneId.systemDefault()).toInstant()));
                for(Coverage item: results){
                    // Delete any old copies that might be the same resource
                    //ehrCoverageRepository.deleteBySourceIdAndIdentifier(medicareId, item.getId());

                    // Add a new copy of the resource
                    coverages.add(ehrCoverageRepository.save(new EhrCoverageRecord(crosswalk.getPatientId(), item,
                            medicareId)));
                }
            }

            return ResponseEntity.ok(coverages);
        }
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/visits")
    public ResponseEntity<List<EhrVisitRecord>> fetchVisits(String source){
        if(source.equals("medicare")){
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }
            EhrPatientCrosswalk crosswalk = ehrService.getCrosswalk(medicareId);
            List<EhrVisitRecord> visits =
                    ehrVisitRecordRepository.findByPatientIdAndSourceId(
                            crosswalk.getPatientId(), medicareId);
            if (visits.isEmpty()){
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(crosswalk.getToken());
                for(ExplanationOfBenefit item: results){
                    // Add/Update the resource
                    visits.add(ehrVisitRecordRepository.save(new EhrVisitRecord(crosswalk.getPatientId(), item, medicareId)));
                }

            }else if(ChronoUnit.DAYS.between(visits.get(0).getSourceUpdatedAt(), LocalDateTime.now()) < 1) {
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(crosswalk.getToken(),
                        Date.from(visits.get(0).getSourceUpdatedAt().atZone(ZoneId.systemDefault()).toInstant()));
                for(ExplanationOfBenefit item: results){

                    // Add/Update the resource
                    visits.add(ehrVisitRecordRepository.save(new EhrVisitRecord(crosswalk.getPatientId(), item, medicareId)));
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