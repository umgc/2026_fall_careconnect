package com.careconnect.controller.ehr;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.ehr.*;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.*;

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
    private MedicareConnectionService connections;


    private final MedicareProperties properties = new MedicareProperties();
    private final MedicareResponseMapper mapper = new MedicareResponseMapper();
    private final ObjectMapper jsonmapper = new ObjectMapper();

    @GetMapping("/v1/api/{source}/patient")
    public ResponseEntity<Object> fetchIdentity(@PathVariable String source){
        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")){

            // Why on earth did we need a single database lookup for a single, unchanging numerical ID instead of hardcoding it?
            // Cause you can't really do that lookup on Bean construction, so you just have to do it lazily, I guess.
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }


            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }

            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();

            // See what data we have cached.
            Optional<EhrSourceIdentity> identities =
                    ehrIdentityRepository.findByPatientIdAndSourceId(
                            crosswalk.getPatientId(), medicareId);

            EhrSourceIdentity toreturn;
            // Our data is either nonexistant or potentially outdated.
            if(identities.isEmpty() ||
                    ChronoUnit.DAYS.between(identities.orElseThrow().getSourceUpdatedAt(), LocalDateTime.now()) > 0){
                Patient results = medicareService.requestMedicarePatientInfo(connections.requireAccessToken(crosswalk));

                // Add the new one.
                EhrSourceIdentity identity = new EhrSourceIdentity(crosswalk.getPatientId(), results, medicareId);
                if(identities.isPresent()){
                    identity.setId(identities.orElseThrow().getId());
                }
                toreturn = ehrIdentityRepository.save(identity);
            }else{
                // Our cached data is fine. Use it.
                toreturn = identities.orElseThrow();
            }

        return ResponseEntity.ok(MedicareEnvelope.ofSingle(
                properties.getMode(),
                properties.isMock(),
                mapper.toPatientView(jsonmapper.valueToTree(toreturn))));
        }

        // An invalid source was requested. 404 them.
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/{source}/coverage")
    public ResponseEntity<Object> fetchCoverage(@PathVariable String source){

        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")) {

            // Why on earth did we need a database lookup for a single numerical ID instead of hardcoding it?
            // Cause you can't really do that on Bean construction, so you just have to do it lazily, I guess.
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }


            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }

            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
            List<EhrCoverageRecord> coverages =
                    ehrCoverageRepository.findByPatientIdAndSourceId(
                            crosswalk.getPatientId(), medicareId);

            // Has this user never retrieved this data?
            if (coverages.isEmpty()){
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(connections.requireAccessToken(crosswalk));
                for(Coverage item: results){
                    coverages.add(ehrCoverageRepository.save(new EhrCoverageRecord(crosswalk.getPatientId(), item, medicareId)));
                }

                // Is the data more than one day old?
            }else if(ChronoUnit.DAYS.between(coverages.get(0).getSourceUpdatedAt(), LocalDateTime.now()) > 0) {

                // Pull in any newer data than the last time we looked
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(connections.requireAccessToken(crosswalk),
                        Date.from(coverages.get(0).getSourceUpdatedAt().atZone(ZoneId.systemDefault()).toInstant()));


                for(Coverage item: results){
                    // The tricky part is that some of this data might overwrite existing data in the database

                    EhrCoverageRecord tosave =   new EhrCoverageRecord(crosswalk.getPatientId(), item, medicareId);
                    for(EhrCoverageRecord record: coverages){
                        // We're updating this entry instead of adding a new one, done by stealing its ID.
                        if(record.getExternalCoverageId().equals(item.getContractFirstRep().getDisplay())){
                            tosave.setId(record.getId());
                            break;
                        }
                    }
                    coverages.add(ehrCoverageRepository.save(tosave));
                }
            }
            // ELSE: The data is sufficiently fresh already, just proceed with what we have cached

        // For some reason the streaming interface really hates valueToTree, so this is my workaround.
        ArrayList<JsonNode> coveragesJson = new ArrayList<>();
            for(EhrCoverageRecord record: coverages){
                coveragesJson.add(jsonmapper.valueToTree(record));
            }
        return ResponseEntity.ok(MedicareEnvelope.of(properties.getMode(), properties.isMock(), mapper.toCoverageView(coveragesJson)));
        }
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/{source}/visits")
    public ResponseEntity<Object> fetchVisits(@PathVariable String source){
        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")){
            // Why on earth did we need a database lookup for a single numerical ID instead of hardcoding it?
            // Cause you can't really do that on Bean construction, so you just have to do it lazily, I guess.
            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }
            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }
            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();

            List<EhrVisitRecord> visits =
                    ehrVisitRecordRepository.findByPatientIdAndSourceId(
                            crosswalk.getPatientId(), medicareId);

            // Has this user never retrieved this data?
            if (visits.isEmpty()){
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(connections.requireAccessToken(crosswalk));
                for(ExplanationOfBenefit item: results){
                    // Add/Update the resource
                    visits.add(ehrVisitRecordRepository.save(new EhrVisitRecord(crosswalk.getPatientId(), item, medicareId)));
                }

                // Is the data more than one day old?
            }else if(ChronoUnit.DAYS.between(visits.get(0).getSourceUpdatedAt(), LocalDateTime.now()) > 0) {
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(connections.requireAccessToken(crosswalk),
                        Date.from(visits.get(0).getSourceUpdatedAt().atZone(ZoneId.systemDefault()).toInstant()));
                for(ExplanationOfBenefit item: results){

                    EhrVisitRecord tosave = new EhrVisitRecord(crosswalk.getPatientId(), item, medicareId);
                    for(EhrVisitRecord record: visits){
                        // We're updating this entry instead of adding a new one, done by stealing its ID.
                        if(record.getExternalVisitId().equals(tosave.getExternalVisitId())){
                            tosave.setId(record.getId());
                            break;
                        }
                    }
                    // Add/Update the resource
                    visits.add(ehrVisitRecordRepository.save(tosave));
                }
            }
            // ELSE: The data is sufficiently fresh already, just proceed with what we have cached

        // For some reason the streaming interface really hates valueToTree, so this is my workaround.
        ArrayList<JsonNode> visitsJson = new ArrayList<>();
        for(EhrVisitRecord record: visits){
            visitsJson.add(jsonmapper.valueToTree(record));
        }
            return ResponseEntity.ok(MedicareEnvelope.of(properties.getMode(), properties.isMock(), mapper.toVisitView(visitsJson)));
        }
        return ResponseEntity.notFound().build();
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