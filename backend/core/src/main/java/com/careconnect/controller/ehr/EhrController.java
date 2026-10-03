package com.careconnect.controller.ehr;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.*;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareService;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

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
    private EhrVisitRecordRepository ehrVisitRecordRepository;

    @Autowired
    private UserRepository userRepo;

    @Autowired
    private EhrPatientCrosswalkRepository  ehrPatientCrosswalkRepository;


    @GetMapping("/oauth2/connect")
    public void outgoing(@RequestParam("where") String where, Authentication authentication, HttpSession session, HttpServletResponse response) throws IOException, ServletException {
        Long userId = 555L; /*userRepo.findByEmail(authentication.getName()).orElseThrow().getId();*/
        if(where.equalsIgnoreCase("medicare")) {

            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }

            Optional<EhrPatientCrosswalk> crosswalk = ehrPatientCrosswalkRepository.findByPatientIdAndSourceId(userId, medicareId);

            if(crosswalk.isEmpty()){

                String linkToken =  UUID.randomUUID().toString();
                log.info("Crosswalk currently empty! Building with user {} and Session {} Link token: {}",
                        userId, session.getId(), linkToken);

                EhrPatientCrosswalk toadd = new EhrPatientCrosswalk();
                toadd.setLinkToken(linkToken);
                toadd.setSourceId(medicareId);
                toadd.setPatientId(userId);
                toadd.setExternalPatientId("");
                ehrPatientCrosswalkRepository.save(toadd);
                session.setAttribute(where, linkToken);
            }

        }
        response.sendRedirect("/oauth2/authorization/" + where);
    }



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

                // Add the new one.
                EhrSourceIdentity identity = new EhrSourceIdentity(crosswalk.getPatientId(), results, medicareId);
                if(identities.isPresent()){
                    identity.setId(identities.orElseThrow().getId());
                }
                toreturn = ehrIdentityRepository.save(identity);
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