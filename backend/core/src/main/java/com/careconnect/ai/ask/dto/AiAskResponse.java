package com.careconnect.ai.ask.dto;

import java.time.LocalDateTime;
import java.util.List;
import lombok.Builder;
import lombok.Data;

/**
 * Response DTO for the Ask AI endpoint.
 * Returns a grounded answer with citations and escalation flag.
 */
@Data
@Builder
public class AiAskResponse {

  /** The AI-generated answer grounded in patient records. */
  private String answer;

  /** Source citations supporting the answer. */
  private List<AiAskCitationDTO> citations;

  /** Medical disclaimer shown with every response. */
  private String disclaimer;

  /**
   * Escalation flag per SRS Table 8.
   * Values: null (no escalation), "confirm-with-provider",
   * "hold-for-review", "crisis-guidance"
   */
  private String escalation;

  /** Whether the response was held for human review (Tier 2). */
  private boolean heldForReview;

  /** Timestamp of when the response was generated. */
  private LocalDateTime generatedAt;

  /** Session ID for audit correlation. */
  private String sessionId;

  /**
   * Citation linking the answer to a specific source record.
   */
  @Data
  @Builder
  public static class AiAskCitationDTO {

    /** Source type: TRANSCRIPT, CLINICAL_NOTE, MEDICATION, etc. */
    private String type;

    /** Source record ID. */
    private String id;

    /** Brief excerpt from the source. */
    private String excerpt;

    /** Speaker or author of the source record. */
    private String speaker;

    /** Date of the source record. */
    private String date;
  }
}