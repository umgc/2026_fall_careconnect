package com.careconnect.dto;

/**
 * Error count and share-of-total for a coarse endpoint bucket.
 */
public record EndpointErrorCountDTO(String endpoint, long count, double rate) {
}
