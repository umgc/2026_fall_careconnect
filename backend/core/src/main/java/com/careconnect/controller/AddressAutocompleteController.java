package com.careconnect.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

/**
 * Proxy controller for Google Places API requests.
 * Keeps API key secure on backend (not exposed in client code).
 * Avoids CORS issues by proxying through backend.
 */
@RestController
@RequestMapping("/v1/api/address")
@Tag(name = "Address", description = "Address autocomplete and Place Details endpoints")
public class AddressAutocompleteController {

    private static final String PLACES_AUTOCOMPLETE_URL = "https://maps.googleapis.com/maps/api/place/autocomplete/json";
    private static final String PLACES_DETAILS_URL = "https://maps.googleapis.com/maps/api/place/details/json";
    private final RestTemplate restTemplate = new RestTemplate();
    @Value("${google.places.api-key:}")
    private String googlePlacesApiKey;

    /**
     * Get address suggestions from Google Places API
     *
     * @param input User's partial address input
     * @return Google Places autocomplete predictions
     */
    @GetMapping("/suggestions")
    @Operation(
            summary = "Get address suggestions",
            description = "Returns address suggestions from Google Places Autocomplete API based on user input"
    )
    public ResponseEntity<Map<String, Object>> getAddressSuggestions(
            @Parameter(description = "Partial address input") @RequestParam String input) {

        // If no API key configured, return empty suggestions
        if (googlePlacesApiKey == null || googlePlacesApiKey.isEmpty()) {
            Map<String, Object> response = new HashMap<>();
            response.put("predictions", new java.util.ArrayList<>());
            response.put("status", "NO_API_KEY");
            return ResponseEntity.ok(response);
        }

        try {
            String encodedInput = URLEncoder.encode(input, StandardCharsets.UTF_8);
            String url = String.format(
                    "%s?input=%s&key=%s&components=country:us&type=geocode",
                    PLACES_AUTOCOMPLETE_URL,
                    encodedInput,
                    googlePlacesApiKey
            );

            Map<String, Object> response = restTemplate.getForObject(url, Map.class);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("status", "ERROR");
            errorResponse.put("message", "Failed to fetch suggestions: " + e.getMessage());
            return ResponseEntity.status(500).body(errorResponse);
        }
    }

    /**
     * Get detailed place information including address components
     *
     * @param placeId Google Place ID
     * @return Detailed place information
     */
    @GetMapping("/details")
    @Operation(
            summary = "Get place details",
            description = "Returns detailed information about a place including address components and geometry"
    )
    public ResponseEntity<Map<String, Object>> getPlaceDetails(
            @Parameter(description = "Google Place ID") @RequestParam String placeId) {

        // If no API key configured, return error
        if (googlePlacesApiKey == null || googlePlacesApiKey.isEmpty()) {
            Map<String, Object> response = new HashMap<>();
            response.put("status", "NO_API_KEY");
            return ResponseEntity.ok(response);
        }

        try {
            String url = String.format(
                    "%s?place_id=%s&key=%s&fields=formatted_address,address_components,geometry",
                    PLACES_DETAILS_URL,
                    placeId,
                    googlePlacesApiKey
            );

            Map<String, Object> response = restTemplate.getForObject(url, Map.class);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("status", "ERROR");
            errorResponse.put("message", "Failed to fetch place details: " + e.getMessage());
            return ResponseEntity.status(500).body(errorResponse);
        }
    }
}
