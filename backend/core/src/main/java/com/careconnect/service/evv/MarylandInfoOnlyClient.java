package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class MarylandInfoOnlyClient implements EvvIntegrationClient {
    @Override
    public String destination() {
        return "maryland-only-info";
    }

    @Override
    public void submit(EvvRecord record) {
        log.info("[MD] informational only for record {}", record.getId());
    }

}
