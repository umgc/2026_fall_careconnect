package com.careconnect.controller;

import com.careconnect.dto.StmlBriefDTO;
import com.careconnect.dto.StmlCheckInDTO;
import com.careconnect.dto.StmlRecallRequest;
import com.careconnect.dto.StmlRecallResponse;
import com.careconnect.dto.StmlSearchRequest;
import com.careconnect.dto.StmlSearchResponse;
import com.careconnect.service.StmlCheckInService;
import com.careconnect.service.StmlRecallService;
import com.careconnect.service.StmlSearchService;
import com.careconnect.service.StmlService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Controller for STML (Short-Term Memory Support) endpoints.
 */
@RestController
@RequestMapping("/v1/api/stml")
@RequiredArgsConstructor
public class StmlController {

  private final StmlService stmlService;
  private final StmlRecallService stmlRecallService;
  private final StmlCheckInService stmlCheckInService;
  private final StmlSearchService stmlSearchService;

  /**
   * STML-2: Returns the daily memory brief for a patient.
   *
   * @param patientId the ID of the patient
   * @return the daily memory brief
   */
  @GetMapping("/patients/{patientId}/brief")
  public ResponseEntity<StmlBriefDTO> getDailyBrief(
      @PathVariable final Long patientId) {
    return ResponseEntity.ok(stmlService.getDailyBrief(patientId));
  }

  /**
   * STML-1: Answers a patient recall question from their care records.
   *
   * @param patientId the ID of the patient
   * @param request   the recall request containing the question
   * @return the recall response with AI answer and citations
   */
  @PostMapping("/patients/{patientId}/recall")
  public ResponseEntity<StmlRecallResponse> recall(
      @PathVariable final Long patientId,
      @RequestBody final StmlRecallRequest request) {
    request.setPatientId(patientId);
    return ResponseEntity.ok(stmlRecallService.recall(request));
  }

  /**
   * STML-3: Returns a consent-gated check-in preparation view for caregivers.
   *
   * @param patientId   the ID of the patient
   * @param caregiverId the ID of the caregiver requesting access
   * @return the check-in preparation view
   */
  @GetMapping("/patients/{patientId}/checkin")
  public ResponseEntity<StmlCheckInDTO> getCheckInView(
      @PathVariable final Long patientId,
      @RequestParam final Long caregiverId) {
    return ResponseEntity.ok(
        stmlCheckInService.getCheckInView(patientId, caregiverId));
  }

  /**
   * STML-4: Searches recall history by keyword, sender, or date.
   *
   * @param patientId the ID of the patient
   * @param request   the search request with filters
   * @return the search response with matching results
   */
  @PostMapping("/patients/{patientId}/search")
  public ResponseEntity<StmlSearchResponse> search(
      @PathVariable final Long patientId,
      @RequestBody final StmlSearchRequest request) {
    request.setPatientId(patientId);
    return ResponseEntity.ok(stmlSearchService.search(request));
  }
}