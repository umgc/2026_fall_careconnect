package com.careconnect.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.*;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class VoiceIntentRequest {

    @NotBlank(message = "Utterance is required")
    @Size(max = 500, message = "Utterance cannot exceed 500 characters")
    private String utterance;

    @Builder.Default
    private String locale = "en";

    private String screenId;
}
