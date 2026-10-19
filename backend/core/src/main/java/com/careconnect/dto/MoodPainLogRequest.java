package com.careconnect.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MoodPainLogRequest {

    @NotNull(message = "Mood value is required")
    @Min(value = 1, message = "Mood value must be between 1 and 10")
    @Max(value = 10, message = "Mood value must be between 1 and 10")
    private Integer moodValue;

    @NotNull(message = "Pain value is required")
    @Min(value = 0, message = "Pain value must be between 0 and 10")
    @Max(value = 10, message = "Pain value must be between 0 and 10")
    private Integer painValue;

    private String note;

    @NotNull(message = "Timestamp is required")
    private LocalDateTime timestamp;
}
