package com.careconnect.model;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum Gender {
    MALE("Male"),
    FEMALE("Female"),
    OTHER("Other"),
    PREFER_NOT_TO_SAY("Prefer not to say");

    private final String displayName;

    Gender(String displayName) {
        this.displayName = displayName;
    }

    @JsonCreator
    public static Gender fromString(String value) {
        if (value == null) {
            return null;
        }

        // Handle case-insensitive input
        String upperValue = value.toUpperCase().trim();

        try {
            return Gender.valueOf(upperValue);
        } catch (IllegalArgumentException e) {
            // Handle common variations
            switch (upperValue) {
                case "M":
                    return MALE;
                case "F":
                    return FEMALE;
                case "PREFER_NOT_TO_SAY":
                case "PREFERNOTTOSAY":
                case "NOT_SAY":
                case "PREFER NOT TO SAY":
                    return PREFER_NOT_TO_SAY;
                default:
                    throw new IllegalArgumentException("Invalid gender value: " + value +
                            ". Valid values are: male, female, other, prefer_not_to_say");
            }
        }
    }

    public String getDisplayName() {
        return displayName;
    }

    @JsonValue
    public String getValue() {
        return this.name().toLowerCase();
    }

    @Override
    public String toString() {
        return displayName;
    }
}
