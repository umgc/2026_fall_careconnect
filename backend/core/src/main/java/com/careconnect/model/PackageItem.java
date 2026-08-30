package com.careconnect.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.*;

import java.time.OffsetDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PackageItem {
    private String trackingNumber;
    private String sender;

    @JsonProperty("expectedDateIso")
    private OffsetDateTime expectedDeliveryDate;  // null if unknown

    @JsonProperty("actions")
    private ActionLinks actionLinks;
}
