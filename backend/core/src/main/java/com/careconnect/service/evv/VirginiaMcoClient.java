package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class VirginiaMcoClient implements EvvIntegrationClient {
    @Override
    public String destination() {
        return "virginia-mco";
    }

    @Override
    public void submit(EvvRecord record) {
        log.info("[VA] submitted to MCO vendor for record {}", record.getId());
    }
}
