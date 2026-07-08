package com.careconnect.ai.ask.dto;

import lombok.Data;

/**
 * Request DTO for the Ask AI endpoint.
 * Accepts a natural-language question for grounded retrieval.
 */
@Data
public class AiAskRequest {

  /** User question (text or transcribed voice). */
  private String query;

  /** Optional conversation session ID for audit correlation. */
  private String sessionId;

  /** Patient ID — populated from JWT or path variable. */
  private Long patientId;

  /** User ID — populated from JWT. */
  private Long userId;
}