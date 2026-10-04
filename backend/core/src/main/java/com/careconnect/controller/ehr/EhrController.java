package com.careconnect.controller.ehr;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.ehr.*;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.random.RandomGenerator;
import java.util.stream.Collectors;

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


    private final MedicareProperties properties = new MedicareProperties();
    private final MedicareResponseMapper mapper = new MedicareResponseMapper();
    private final ObjectMapper jsonmapper = new ObjectMapper();

    @GetMapping("/oauth2/connect")
    // Glues a linkId onto your session, builds a crosswalk to store it and your destination,
    // then redirects you to the endpoint the framework manages.
    public void outgoing(@RequestParam("where") String where, Authentication authentication, HttpSession session, HttpServletResponse response) throws IOException, ServletException {

        Long userId = userRepo.findByEmail(authentication.getName()).orElseThrow().getId();


        if(where.equalsIgnoreCase("medicare")) {

            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }

            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrPatientCrosswalkRepository.findByPatientIdAndSourceId(userId, medicareId);

            if(crosswalkOpt.isEmpty()){

                String linkToken =  UUID.randomUUID().toString();
                log.info("Crosswalk currently empty! Building with user {} and Session {} Link token: {}",
                        userId, session.getId(), linkToken);

                EhrPatientCrosswalk toadd = new EhrPatientCrosswalk();

                // Set up what we do know
                toadd.setLinkToken(linkToken);
                toadd.setSourceId(medicareId);
                toadd.setPatientId(userId);

                // We don't know this yet, but can't leave it null.
                toadd.setExternalPatientId("");
                ehrPatientCrosswalkRepository.save(toadd);
                session.setAttribute(where, linkToken);
            }else{
                // Re-Authenticating to keep the long login up to date. Still needs a fresh linkToken
                EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
                String linkToken =  UUID.randomUUID().toString();
                crosswalk.setLinkToken(linkToken);
                ehrPatientCrosswalkRepository.save(crosswalk);
                session.setAttribute(where, linkToken);
            }


        }
        response.sendRedirect("/oauth2/authorization/" + where);
    }

    @GetMapping("/v1/api/medicare/disconnect")
    public ResponseEntity<String> revoke(){
        Long medicareId = medicareService.getId();
        if(medicareId == null){
            medicareService.retrieveId();
            medicareId = medicareService.getId();
        }
        Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
        if(crosswalkOpt.isEmpty()){
            return ResponseEntity.notFound().build();
        }
        EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
        medicareService.revoke(crosswalk.getToken());
        ehrPatientCrosswalkRepository.delete(crosswalk);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/v1/api/medicare/status")
    public ResponseEntity<String> status(){
        Long medicareId = medicareService.getId();
        if(medicareId == null){
            medicareService.retrieveId();
            medicareId = medicareService.getId();
        }
        Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
        if(crosswalkOpt.isEmpty()){
            return ResponseEntity.notFound().build();
        }
        // I guess just return if you have medicare linked?
        // Really not sure what kind of status I could be pulling right now.
        return ResponseEntity.ok().build();
    }

    @GetMapping("/v1/api/medicare/patient")
    public ResponseEntity<Object> fetchIdentity(){

        /*if(source.equals("medicare")){*/
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }
            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                return ResponseEntity.notFound().build();
            }
            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
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

        return ResponseEntity.ok(MedicareEnvelope.ofSingle(properties.getMode(), properties.isMock(), mapper.toPatientView(jsonmapper.valueToTree(toreturn))));
        /*}*/

        /*return ResponseEntity.notFound().build();*/
    }

    @GetMapping("/v1/api/medicare/coverage")
    public ResponseEntity<Object> fetchCoverage(String source){

        /*if(source.equals("medicare")) {*/
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }
            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                return ResponseEntity.notFound().build();
            }
            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
            List<EhrCoverageRecord> coverages =
                    ehrCoverageRepository.findByPatientIdAndSourceId(
                            crosswalk.getPatientId(), medicareId);
            if (coverages.isEmpty()){
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(crosswalk.getToken());
                for(Coverage item: results){
                    // TODO actual repalcement logic
                    coverages.add(ehrCoverageRepository.save(new EhrCoverageRecord(crosswalk.getPatientId(), item, medicareId)));
                }

            }else if(ChronoUnit.DAYS.between(coverages.get(0).getSourceUpdatedAt(), LocalDateTime.now()) < 1) {
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(crosswalk.getToken(),
                        Date.from(coverages.get(0).getSourceUpdatedAt().atZone(ZoneId.systemDefault()).toInstant()));
                for(Coverage item: results){
                    // TODO actual replacement logic

                    // Add a new copy of the resource
                    coverages.add(ehrCoverageRepository.save(new EhrCoverageRecord(crosswalk.getPatientId(), item,
                            medicareId)));
                }
            }

        // For some reason the streaming interface really hates valueToTree, so this is my workaround.
        ArrayList<JsonNode> coveragesJson = new ArrayList<>();
            for(EhrCoverageRecord record: coverages){
                coveragesJson.add(jsonmapper.valueToTree(record));
            }
        return ResponseEntity.ok(MedicareEnvelope.of(properties.getMode(), properties.isMock(), mapper.toCoverageView(coveragesJson)));
        /*}
        return ResponseEntity.notFound().build();*/
    }

    // TODO: negotiate a better set of endpoints that allows most Ehr code to be in one place.
    @GetMapping("/v1/api/medicare/visits")
    public ResponseEntity<Object> fetchVisits(String source){
        /*if(source.equals("medicare")){*/
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }
            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                return ResponseEntity.notFound().build();
            }
            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();

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

        // For some reason the streaming interface really hates valueToTree, so this is my workaround.
        ArrayList<JsonNode> visitsJson = new ArrayList<>();
        for(EhrVisitRecord record: visits){
            visitsJson.add(jsonmapper.valueToTree(record));
        }
            return ResponseEntity.ok(MedicareEnvelope.of(properties.getMode(), properties.isMock(), mapper.toVisitView(visitsJson)));
        /*}
        return ResponseEntity.notFound().build();*/
    }

    /**
     * @return the configured source, or {@code null} when Medicare is switched off for this
     *     environment or the configured mode has no implementation yet
     */
    /*private MedicareSource resolveSource() {
        if (!properties.isEnabled()) {
            return null;
        }
        return sources.getIfAvailable();
    }*/

    // TODO: figure out what to do with this.
    private ResponseEntity<Object> unavailable(String source) {
        final String detail = properties.isEnabled()
                ? "No " + source +  " source is registered for mode '" + properties.getMode() + "'."
                : source + " retrieval is disabled for this environment.";
        log.debug("[{}] Request rejected: {}", source, detail);
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of(
                        "source", MedicareProperties.SOURCE_MEDICARE,
                        "error", "medicare_unavailable",
                        "detail", detail));
    }

}