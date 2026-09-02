package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvAuditEvent;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvAuditEventRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Map;

@Component
@RequiredArgsConstructor
public class AuditLogger {
    private final EvvAuditEventRepository repo;

    public void log(EvvRecord rec, Long actorUserId, String type, Map<String, Object> details) {
        repo.save(EvvAuditEvent.builder()
                .evvRecord(rec)
                .actorUserId(actorUserId)
                .eventType(type)
                .deviceInfo(rec.getDeviceInfo())
                .details(details)
                .build());
    }
}
