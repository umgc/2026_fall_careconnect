package com.careconnect.dto;

import java.time.Instant;

public record MedicationLastTakenUpdateDTO(
        Instant lastTaken
) {
}
