package com.careconnect.dto.evv;

import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.model.evv.EvvLocationType;
import com.careconnect.model.evv.NoGpsReason;
import lombok.*;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EvvLocationResponse {

    private UUID id;
    private Long evvRecordId;
    private EvvLocationRole role;
    private EvvLocationType type;
    private BigDecimal latitude;
    private BigDecimal longitude;
    private BigDecimal accuracyM;
    private Map<String, Object> addressSnapshot;
    private NoGpsReason noGpsReason;
    private String manualAddress;
    private OffsetDateTime createdAt;
}

