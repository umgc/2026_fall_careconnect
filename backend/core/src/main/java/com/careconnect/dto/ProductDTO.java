package com.careconnect.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import lombok.Builder;

import java.time.Instant;
import java.util.List;

@Builder

public record ProductDTO(
        String id,
        boolean active,
        String name
) {
}