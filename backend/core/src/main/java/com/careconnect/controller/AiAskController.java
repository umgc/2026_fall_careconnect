package com.careconnect.controller;

import com.careconnect.ai.ask.dto.AiAskRequest;
import com.careconnect.ai.ask.dto.AiAskResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Controller for the Ask AI endpoint.
 * Accepts natural-language questions and returns grounded answers
 * with citations drawn from the patient's stored records.
 */
@Slf4j
@RestController
@RequestMapping("/v1/api/ai")
@RequiredArgsConstructor
public class AiAskController {

  /**
   * Ask AI — submit a natural-language question for grounded retrieval.
   * Returns a grounded answer with citations, disclaimer, and escalation flag.
   *
   * @param patientId the ID of the patient
   * @param request   the ask request containing the query and session ID
   * @return grounded answer with citations
   */
  @PostMapping("/patients/{patientId}/ask")
  public ResponseEntity<AiAskResponse> ask(
      @PathVariable final Long patientId,
      @RequestBody final AiAskRequest request) {
    request.setPatientId(patientId);
    log.info("Ask AI request for patient {} session {}",
        patientId, request.getSessionId());

    // Placeholder response until AiAskOrchestrator is built
    AiAskResponse response = AiAskResponse.builder()
        .answer("Ask AI is being set up. Please check back soon.")
        .citations(java.util.List.of())
        .disclaimer(
            "This information is drawn from your care records."
            + " It is not medical advice.")
        .escalation(null)
        .heldForReview(false)
        .generatedAt(java.time.LocalDateTime.now())
        .sessionId(request.getSessionId())
        .build();

    return ResponseEntity.ok(response);
  }
}