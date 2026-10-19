package com.careconnect.model;

import com.fasterxml.jackson.annotation.JsonProperty;

import lombok.*;


@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PatientNotetakerKeyword {

    @JsonProperty("keyword")
    private String keyword;

    @JsonProperty("event_type")
    private EventType eventType;

    public enum EventType {
        ALERT,
        TASK
    }
}


