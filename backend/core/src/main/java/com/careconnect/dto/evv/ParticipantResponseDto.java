package com.careconnect.dto.evv;

import lombok.*;

import java.time.OffsetDateTime;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ParticipantResponseDto {
    private Long id;
    private String patientName;
    private String maNumber;
    private OffsetDateTime createdAt;
    private String createdBy;
}
