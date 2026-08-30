package com.careconnect.dto;

import com.careconnect.model.Allergy.AllergyType;
import com.careconnect.model.Allergy.AllergySeverity;
import com.fasterxml.jackson.annotation.JsonAlias;
import lombok.Builder;

@Builder
public record AllergyDTO(
        Long id,

        Long patientId,

        // New canonical: allergen
        // Also accept legacy names the old clients might send
        @JsonAlias({"medicationName", "drugOrAllergen", "drug"})
        String allergen,

        // New canonical: allergyType (enum)
        // If any legacy clients sent "type", accept it too
        @JsonAlias({"type"})
        AllergyType allergyType,

        // New canonical: severity (enum)
        // If old clients used "level", accept it
        @JsonAlias({"level"})
        AllergySeverity severity,

        // New canonical: reaction
        @JsonAlias({"allergicReaction"})
        String reaction,

        String notes,

        // Keep canonical "diagnosedDate" but also accept common legacy names
        @JsonAlias({"dateRecorded", "createdOn"})
        String diagnosedDate,

        // Keep canonical "isActive" but accept "active"
        @JsonAlias({"active"})
        Boolean isActive
) {
}
