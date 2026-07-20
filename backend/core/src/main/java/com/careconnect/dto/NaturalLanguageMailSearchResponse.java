package com.careconnect.dto;

import java.util.List;

/**
 * Response envelope for natural-language mail search (Task 3.14.7 / #124).
 */
public record NaturalLanguageMailSearchResponse(
        Long patientId,
        String query,
        List<String> tokens,
        int totalMatches,
        List<NaturalLanguageMailSearchMatch> matches
) {
}
