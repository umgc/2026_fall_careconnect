package com.careconnect.controller.ehr;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.ehr.*;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.core.JsonProcessingException;
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
import java.time.OffsetDateTime;
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
    private EhrRawPayloadRepository ehrRawPayloadRepository;


    @Autowired
    private MedicareConnectionService connections;

    @Autowired
    private MedicareProperties properties;

    private final MedicareResponseMapper mapper = new MedicareResponseMapper();
    private final ObjectMapper jsonmapper = new ObjectMapper();

    @GetMapping("/v1/api/{source}/patient")
    public ResponseEntity<Object> fetchIdentity(@PathVariable String source) throws JsonProcessingException {

        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")){

            Long medicareId = medicareService.getId();

            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }

            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();

            JsonNode toreturn;
            OffsetDateTime retrievedTime;
            // See what data we have cached.
            Optional<EhrRawPayload> lastIdentity =
                    ehrRawPayloadRepository.findFirstByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDesc(
                            crosswalk.getPatientId(), medicareId, "SourceIdentity");

            // Our data is either nonexistant or potentially outdated.
            if(lastIdentity.isEmpty() ||
                    ChronoUnit.DAYS.between(lastIdentity.orElseThrow().getCreatedAt(), LocalDateTime.now()) > 0){
                Patient results = medicareService.requestMedicarePatientInfo(connections.requireAccessToken(crosswalk));

                EhrSourceIdentity identity = new EhrSourceIdentity(crosswalk.getPatientId(), results, medicareId);


                Optional<EhrSourceIdentity> identities =
                        ehrIdentityRepository.findByPatientIdAndSourceId(
                                crosswalk.getPatientId(), medicareId);

                // Add the new one.
                if(lastIdentity.isPresent()){
                    identity.setId(identities.orElseThrow().getId());
                }

                 ehrRawPayloadRepository.save(ehrService.patientToRawPayload(results, crosswalk.getPatientId(), OffsetDateTime.now(), medicareId));
                 ehrIdentityRepository.save(identity);
                 toreturn = ehrService.patientToNode(results);
                 retrievedTime = OffsetDateTime.now();
            }else{
                // Our cached data is fine. Use it.
                toreturn = jsonmapper.readTree(lastIdentity.orElseThrow().getPayload());
                retrievedTime = lastIdentity.orElseThrow().getRetrievedAt();
            }

        return ResponseEntity.ok(MedicareEnvelope.ofSingle(
                properties.getMode(),
                properties.isMock(),
                mapper.toPatientView(toreturn),
                retrievedTime));
        }

        // An invalid source was requested. 404 them.
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/{source}/coverage")
    public ResponseEntity<Object> fetchCoverage(@PathVariable String source) throws JsonProcessingException {

        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")) {
            Long medicareId = medicareService.getId();


            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }

            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
            Long patientId = crosswalk.getPatientId();

            List<EhrRawPayload> cachedCoverages =
                    ehrRawPayloadRepository.findByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDesc(
                            patientId, medicareId, "CoverageRecord");

            List<JsonNode> toreturn = new ArrayList<>();
            OffsetDateTime retrievedTime;
            // Has this user never retrieved this data?
            if (cachedCoverages.isEmpty()){
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(
                        connections.requireAccessToken(crosswalk));


                for(Coverage item: results){
                    ehrCoverageRepository.save(new EhrCoverageRecord(patientId, item, medicareId));
                    ehrRawPayloadRepository.save(ehrService.coverageToRawPayload(item ,patientId,
                                                    OffsetDateTime.now(), medicareId));
                    toreturn.add(ehrService.coverageToNode(item));
                }
                retrievedTime =  OffsetDateTime.now();

                // Is the data more than one day old?
            }else if(ChronoUnit.DAYS.between(cachedCoverages.get(0).getRetrievedAt(), LocalDateTime.now()) > 0) {

                // Pull in any newer data than the last time we looked
                List<Coverage> results = medicareService.requestMedicareCoverageInfo(
                        connections.requireAccessToken(crosswalk),
                        Date.from(cachedCoverages.get(0).getRetrievedAt().toInstant()));

                retrievedTime =  OffsetDateTime.now();

                for(Coverage item: results){
                    // The tricky part is that some of this data might overwrite existing data in the database

                    //EhrCoverageRecord tosave = new EhrCoverageRecord(crosswalk.getPatientId(), item, medicareId);
                    //ehrCoverageRepository.save(tosave);
                    EhrRawPayload candidate = ehrService.coverageToRawPayload(item, patientId, OffsetDateTime.now(), medicareId);
                    for(EhrRawPayload cached: cachedCoverages){
                        if(item.getId().equals(cached.getExternalResourceId())){
                            // If this record already exists in the raw payloads, then take its ID and replace it.
                            candidate.setId(cached.getId());
                            cachedCoverages.remove(cached);
                            break;
                        }
                    }

                    ehrRawPayloadRepository.save(candidate);
                    toreturn.add(ehrService.coverageToNode(item));
                }
            }else{
                retrievedTime = cachedCoverages.get(0).getRetrievedAt();
            }
            for(EhrRawPayload item : cachedCoverages){
                toreturn.add(jsonmapper.readTree(item.getPayload()));
            }

        return ResponseEntity.ok(MedicareEnvelope.of(
                properties.getMode(), properties.isMock(), mapper.toCoverageView(toreturn), retrievedTime));
        }
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/{source}/visits")
    public ResponseEntity<Object> fetchVisits(@PathVariable String source) throws JsonProcessingException {
        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")){
            Long medicareId = medicareService.getId();

            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareId);
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }
            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
            Long patientId = crosswalk.getPatientId();

            //
            List<EhrRawPayload> cachedVisits =
                    ehrRawPayloadRepository.findByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDesc(
                            crosswalk.getPatientId(), medicareId, "VisitRecord");

            List<JsonNode> toreturn = new ArrayList<>();
            OffsetDateTime retrievedTime;

            // Has this user never retrieved this data?
            if (cachedVisits.isEmpty()){
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(connections.requireAccessToken(crosswalk));
                for(ExplanationOfBenefit item: results){
                    // Add/Update the resource
                    ehrVisitRecordRepository.save(new EhrVisitRecord(crosswalk.getPatientId(), item, medicareId));
                    ehrRawPayloadRepository.save(ehrService.eobToRawPayload(item, patientId, OffsetDateTime.now(), medicareId));
                    toreturn.add(ehrService.eobToNode(item));
                }
                retrievedTime = OffsetDateTime.now();

                // Is the data more than one day old?
            }else if(ChronoUnit.DAYS.between(cachedVisits.get(0).getRetrievedAt(), LocalDateTime.now()) > 0) {
                List<ExplanationOfBenefit> results = medicareService.requestMedicareEOBInfo(connections.requireAccessToken(crosswalk),
                        Date.from(cachedVisits.get(0).getRetrievedAt().toInstant()));
                for(ExplanationOfBenefit item: results){
                    // The tricky part is that some of this data might overwrite existing data in the database
                    //ehrVisitRecordRepository.save(new EhrVisitRecord(crosswalk.getPatientId(), item, medicareId));

                    EhrRawPayload candidate = ehrService.eobToRawPayload(item, patientId, OffsetDateTime.now(), medicareId);
                    for(EhrRawPayload cached: cachedVisits){
                        if(item.getId().equals(cached.getExternalResourceId())){
                            // If this record already exists in the raw payloads, then take its ID and replace it.
                            candidate.setId(cached.getId());
                            cachedVisits.remove(cached);
                            break;
                        }
                    }
                    ehrRawPayloadRepository.save(candidate);
                    toreturn.add(ehrService.eobToNode(item));
                }
                retrievedTime = OffsetDateTime.now();
            }else{
                // ELSE: The data is sufficiently fresh already, just proceed with what we have cached
                retrievedTime = cachedVisits.get(0).getRetrievedAt();
            }
            for(EhrRawPayload item : cachedVisits){
                toreturn.add(jsonmapper.readTree(item.getPayload()));
            }


            return ResponseEntity.ok(MedicareEnvelope.of(properties.getMode(),
                    properties.isMock(),
                    mapper.toVisitView(toreturn),
                    retrievedTime));
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