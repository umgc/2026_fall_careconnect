package com.careconnect.dto;

import com.careconnect.model.Gender;
import com.careconnect.model.Address;
import lombok.Builder;

@Builder
public record PatientSummaryDTO(
        Long id,
        String firstName,
        String lastName,
        String email,
        String phone,
        String dob,
        Gender gender,
        Address address,
        String relationship,
        String maNumber
) {
}
