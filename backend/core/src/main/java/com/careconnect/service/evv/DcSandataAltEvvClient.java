package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Slf4j
@Component
@RequiredArgsConstructor
public class DcSandataAltEvvClient implements EvvIntegrationClient {
    private final RestTemplate restTemplate = new RestTemplate();

    @Override
    public String destination() {
        return "dc-sandata";
    }

    @Override
    public void submit(EvvRecord record) throws Exception {
        String url = "https://api.sandata.dc.gov/altevv/Visits";
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.add("x-api-key", "REPLACE_ME");
        String payload = String.format(
                "{\"Calls\":[{\"CallDateTime\":\"%s\",\"CallAssignment\":\"In\",\"Location\":\"%f,%f\"}]}\n",
                record.getTimeIn(), record.getLocationLat(), record.getLocationLng());
        ResponseEntity<String> resp = restTemplate.postForEntity(url, new HttpEntity<>(payload, headers), String.class);
        if (!resp.getStatusCode().is2xxSuccessful()) {
            throw new RuntimeException("Sandata submission failed: " + resp.getStatusCode());
        }
        log.info("[DC] Sandata submitted record {}", record.getId());
    }
}
