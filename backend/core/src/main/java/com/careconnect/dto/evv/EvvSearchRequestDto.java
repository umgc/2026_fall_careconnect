package com.careconnect.dto.evv;

import lombok.*;

import java.time.LocalDate;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EvvSearchRequestDto {

    private String patientName;
    private String serviceType;
    private Long caregiverId;
    private Long patientId;
    private LocalDate startDate;
    private LocalDate endDate;
    private String stateCode;
    private String status;
    @Builder.Default
    private Integer page = 0;
    @Builder.Default
    private Integer size = 20;
    @Builder.Default
    private String sortBy = "createdAt";
    @Builder.Default
    private String sortDirection = "DESC";
}

