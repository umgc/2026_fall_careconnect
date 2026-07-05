package com.careconnect.controller;

import com.careconnect.dto.StmlBriefDTO;
import com.careconnect.dto.StmlRecallRequest;
import com.careconnect.dto.StmlRecallResponse;
import com.careconnect.service.StmlRecallService;
import com.careconnect.service.StmlService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/api/stml")
@RequiredArgsConstructor
public class StmlController {

    private final StmlService stmlService;
    private final StmlRecallService stmlRecallService;

    // STML-2: Daily Memory Brief
    @GetMapping("/patients/{patientId}/brief")
    public ResponseEntity<StmlBriefDTO> getDailyBrief(@PathVariable Long patientId) {
        return ResponseEntity.ok(stmlService.getDailyBrief(patientId));
    }

    // STML-1: Recall — "what did we discuss?"
    @PostMapping("/patients/{patientId}/recall")
    public ResponseEntity<StmlRecallResponse> recall(
            @PathVariable Long patientId,
            @RequestBody StmlRecallRequest request) {
        request.setPatientId(patientId);
        return ResponseEntity.ok(stmlRecallService.recall(request));
    }
}