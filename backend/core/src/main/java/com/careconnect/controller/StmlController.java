package com.careconnect.controller;

import com.careconnect.dto.StmlBriefDTO;
import com.careconnect.dto.StmlCheckInDTO;
import com.careconnect.dto.StmlRecallRequest;
import com.careconnect.dto.StmlRecallResponse;
import com.careconnect.dto.StmlSearchRequest;
import com.careconnect.dto.StmlSearchResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.StmlCheckInService;
import com.careconnect.service.StmlRecallService;
import com.careconnect.service.StmlSearchService;
import com.careconnect.service.StmlService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Controller for STML (Short-Term Memory Support) endpoints.
 * All endpoints are gated by RetrievalScopeService RBAC checks.
 */
@RestController
@RequestMapping("/v1/api/stml")
@RequiredArgsConstructor
public class StmlController {

  private final StmlService stmlService;
  private final StmlRecallService stmlRecallService;
  private final StmlCheckInService stmlCheckInService;
  private final StmlSearchService stmlSearchService;
  private final RetrievalScopeService retrievalScopeService;
  private final UserRepository userRepository;

  /** Gets the currently authenticated user from the security context. */
  private User getCurrentUser() {
    Authentication auth = SecurityContextHolder.getContext().getAuthentication();
    return userRepository.findByEmail(auth.getName())
        .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
  }

  /** STML-2: Returns the daily memory brief for a patient.
   *
   * @param patientId the ID of the patient
   * @return the daily memory brief
   */
  @GetMapping("/patients/{patientId}/brief")
  public ResponseEntity<StmlBriefDTO> getDailyBrief(
      @PathVariable final Long patientId) {
    try {
      retrievalScopeService.resolveRetrievalScope(getCurrentUser(), patientId);
    } catch (ForbiddenScopeException e) {
      return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
    } catch (UnauthorizedException e) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }
    return ResponseEntity.ok(stmlService.getDailyBrief(patientId));
  }

  /** STML-1: Answers a patient recall question from their care records.
   *
   * @param patientId the ID of the patient
   * @param request   the recall request containing the question
   * @return the recall response with AI answer and citations
   */
  @PostMapping("/patients/{patientId}/recall")
  public ResponseEntity<StmlRecallResponse> recall(
      @PathVariable final Long patientId,
      @RequestBody final StmlRecallRequest request) {
    try {
      retrievalScopeService.resolveRetrievalScope(getCurrentUser(), patientId);
    } catch (ForbiddenScopeException e) {
      return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
    } catch (UnauthorizedException e) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }
    request.setPatientId(patientId);
    return ResponseEntity.ok(stmlRecallService.recall(request));
  }

  /** STML-3: Returns a consent-gated check-in preparation view for caregivers.
   *
   * @param patientId   the ID of the patient
   * @param caregiverId the ID of the caregiver requesting access
   * @return the check-in preparation view
   */
  @GetMapping("/patients/{patientId}/checkin")
  public ResponseEntity<StmlCheckInDTO> getCheckInView(
      @PathVariable final Long patientId,
      @RequestParam final Long caregiverId) {
    User caller = getCurrentUser();
    // caregiverId is client-supplied — without this check, any authenticated
    // user could pass a different caregiver's id and read their consent-gated
    // check-in view. Consent is only meaningful if caregiverId is the caller.
    if (!caller.getId().equals(caregiverId)) {
      return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
    }
    try {
      retrievalScopeService.resolveRetrievalScope(caller, patientId);
    } catch (ForbiddenScopeException e) {
      return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
    } catch (UnauthorizedException e) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }
    return ResponseEntity.ok(
        stmlCheckInService.getCheckInView(patientId, caregiverId));
  }

  /** STML-4: Searches recall history by keyword, sender, or date.
   *
   * @param patientId the ID of the patient
   * @param request   the search request with filters
   * @return the search response with matching results
   */
  @PostMapping("/patients/{patientId}/search")
  public ResponseEntity<StmlSearchResponse> search(
      @PathVariable final Long patientId,
      @RequestBody final StmlSearchRequest request) {
    try {
      retrievalScopeService.resolveRetrievalScope(getCurrentUser(), patientId);
    } catch (ForbiddenScopeException e) {
      return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
    } catch (UnauthorizedException e) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }
    request.setPatientId(patientId);
    return ResponseEntity.ok(stmlSearchService.search(request));
  }
}