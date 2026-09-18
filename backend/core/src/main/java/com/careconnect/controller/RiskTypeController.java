package com.careconnect.controller;

import com.careconnect.model.RiskType;
import com.careconnect.service.PatientRiskService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/v1/api/risk-types")
@Tag(name = "Risk Types", description = "Predefined risk types for client known risks")
@SecurityRequirement(name = "Bearer Authentication")
public class RiskTypeController {

    private final PatientRiskService patientRiskService;

    public RiskTypeController(PatientRiskService patientRiskService) {
        this.patientRiskService = patientRiskService;
    }

    @GetMapping
    @Operation(summary = "Get all risk types", description = "Returns the full predefined list of risk types (e.g. Aspiration Pneumonia, Elopement, Fall with Injury, Self-Harm, Seizures)")
    @ApiResponses({@ApiResponse(responseCode = "200", description = "List of risk types")})
    public ResponseEntity<List<RiskType>> getAllRiskTypes() {
        return ResponseEntity.ok(patientRiskService.getAllRiskTypes());
    }
}
