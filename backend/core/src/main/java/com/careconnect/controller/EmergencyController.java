package com.careconnect.controller;

import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.PatientService;
import com.careconnect.service.VialOfLifePdfService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/api/emergency")
@Tag(name = "Emergency Information", description = "Emergency medical information and Vial of Life PDF generation")
public class EmergencyController {

    private static final Logger LOGGER = LoggerFactory.getLogger(EmergencyController.class);

    @Autowired
    private VialOfLifePdfService vialOfLifePdfService;

    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    @Autowired
    private PatientService patientService;

    /**
     * Interim fix for DEF-EMG-01 until CR-1 Increment 2 replaces these endpoints: only a caller who
     * may see this patient (the patient, a linked caregiver or family member, or an admin, as
     * {@link AuthorizationService#requirePatientAccess} decides) gets the PDF. Everyone else gets the
     * same 404 as an unknown emergency ID, so a refusal does not reveal that the patient exists.
     */
    private boolean mayReadEmergencyData(String emergencyId) {
        if (emergencyId == null || !emergencyId.startsWith("VIAL")) {
            return false;
        }
        try {
            Long patientId = Long.parseLong(emergencyId.substring(4));
            Patient patient = patientService.getPatientById(patientId);
            if (patient == null || patient.getUser() == null) {
                return false;
            }
            // requirePatientAccess compares user ids, so pass the patient's user id, not patient.id.
            authorizationService.requirePatientAccess(securityUtil.resolveCurrentUser(), patient.getUser().getId());
            return true;
        } catch (NumberFormatException | UnauthorizedException | AppException e) {
            return false;
        }
    }

    /**
     * Generate and serve a pre-filled Vial of Life PDF for emergency use
     */
    @GetMapping("/{emergencyId}.pdf")
    @Operation(
            summary = "🚨 Get Emergency PDF",
            description = "Generate a pre-filled Vial of Life PDF document for emergency responders.\n\n"
                    + "This endpoint is designed to be accessed via QR codes in emergency situations.\n"
                    + "It returns an official Vial of Life form pre-populated with the patient's:\n"
                    + "- Basic information (name, DOB, blood type)\n"
                    + "- Critical allergies and medical conditions\n"
                    + "- Current medications\n"
                    + "- Emergency contact information\n\n"
                    + "**Security Note:** This endpoint uses emergency ID tokens for access control.\n",
            tags = {"Emergency Information", "🚨 Emergency Response"}
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "PDF generated and returned successfully"),
            @ApiResponse(responseCode = "404", description = "Patient not found for emergency ID"),
            @ApiResponse(responseCode = "500", description = "Error generating PDF")
    })
    public ResponseEntity<byte[]> getEmergencyPdf(
            @Parameter(description = "Emergency ID (e.g., VIAL123456)", required = true)
            @PathVariable String emergencyId) {

        if (!mayReadEmergencyData(emergencyId)) {
            LOGGER.warn("Emergency PDF refused or not found for ID: {}", emergencyId);
            return ResponseEntity.notFound().build();
        }
        try {
            LOGGER.info("Emergency PDF requested for ID: {}", emergencyId);

            byte[] pdfContent = vialOfLifePdfService.generateVialOfLifePdf(emergencyId);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_PDF);
            headers.set("Content-Disposition", "inline; filename=\"vial-of-life-" + emergencyId + ".pdf\"");
            headers.setContentLength(pdfContent.length);

            return new ResponseEntity<>(pdfContent, headers, HttpStatus.OK);

        } catch (IllegalArgumentException e) {
            LOGGER.warn("Invalid emergency ID: {}", emergencyId);
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            LOGGER.error("Error generating emergency PDF for ID: {}", emergencyId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Download emergency PDF (forces download instead of viewing)
     */
    @GetMapping("/download/{emergencyId}.pdf")
    @Operation(
            summary = "⬇️ Download Emergency PDF",
            description = "Download a pre-filled Vial of Life PDF document (forces download)",
            tags = {"Emergency Information", "🚨 Emergency Response"}
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "PDF downloaded successfully"),
            @ApiResponse(responseCode = "404", description = "Patient not found for emergency ID"),
            @ApiResponse(responseCode = "500", description = "Error generating PDF")
    })
    public ResponseEntity<byte[]> downloadEmergencyPdf(
            @Parameter(description = "Emergency ID (e.g., VIAL123456)", required = true)
            @PathVariable String emergencyId) {

        if (!mayReadEmergencyData(emergencyId)) {
            LOGGER.warn("Emergency PDF refused or not found for ID: {}", emergencyId);
            return ResponseEntity.notFound().build();
        }
        try {
            LOGGER.info("Emergency PDF download requested for ID: {}", emergencyId);

            byte[] pdfContent = vialOfLifePdfService.generateVialOfLifePdf(emergencyId);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_PDF);
            headers.set("Content-Disposition", "attachment; filename=\"vial-of-life-" + emergencyId + ".pdf\"");
            headers.setContentLength(pdfContent.length);

            return new ResponseEntity<>(pdfContent, headers, HttpStatus.OK);

        } catch (IllegalArgumentException e) {
            LOGGER.warn("Invalid emergency ID: {}", emergencyId);
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            LOGGER.error("Error generating emergency PDF for ID: {}", emergencyId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }


    /**
     * Health check endpoint for emergency services
     */
    @GetMapping("/health")
    @Operation(
            summary = "🏥 Emergency Service Health Check",
            description = "Check if emergency PDF generation service is available",
            tags = {"Emergency Information"}
    )
    public ResponseEntity<String> healthCheck() {
        return ResponseEntity.ok("Emergency PDF service is operational");
    }

    /**
     * Debug endpoint to test patient data retrieval
     */
    @GetMapping("/debug/{emergencyId}")
    @Operation(
            summary = "🐛 Debug Patient Data",
            description = "Debug endpoint to check if patient data can be retrieved for an emergency ID",
            tags = {"Emergency Information", "🛠️ Development"}
    )
    public ResponseEntity<String> debugPatientData(
            @Parameter(description = "Emergency ID (e.g., VIAL123456)", required = true)
            @PathVariable String emergencyId) {
        // DEF-EMG-03 interim fix: the debug endpoint answers administrators only; everyone else gets 404.
        User caller = securityUtil.resolveCurrentUser();
        if (caller == null || !caller.isAdmin()) {
            return ResponseEntity.notFound().build();
        }
        try {
            LOGGER.info("Debug: Testing patient data retrieval for emergency ID: {}", emergencyId);

            // Extract patient ID from emergency ID
            Long patientId;
            try {
                if (emergencyId.startsWith("VIAL")) {
                    String idPart = emergencyId.substring(4);
                    patientId = Long.parseLong(idPart);
                } else {
                    return ResponseEntity.badRequest().body("Invalid emergency ID format: " + emergencyId);
                }
            } catch (NumberFormatException e) {
                return ResponseEntity.badRequest().body("Could not parse patient ID from emergency ID: " + emergencyId);
            }

            // Check if services are available
            if (vialOfLifePdfService == null) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("VialOfLifePdfService is null");
            }

            // Try to call the PDF generation to see detailed error
            try {
                byte[] pdfContent = vialOfLifePdfService.generateVialOfLifePdf(emergencyId);
                return ResponseEntity.ok("SUCCESS: PDF generated successfully. Size: " + pdfContent.length + " bytes");
            } catch (Exception e) {
                LOGGER.error("Debug: Error in PDF generation", e);
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body("Error generating PDF: " + e.getClass().getSimpleName() + " - " + e.getMessage());
            }

        } catch (Exception e) {
            LOGGER.error("Debug: Unexpected error", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Unexpected error: " + e.getClass().getSimpleName() + " - " + e.getMessage());
        }
    }
}