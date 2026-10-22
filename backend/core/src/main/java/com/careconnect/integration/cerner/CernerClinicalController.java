package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.integration.cerner.CernerAllergyService.UnknownPatientException;
import com.careconnect.model.ehr.EhrCodeValue;
import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrEncounterParticipantValue;
import com.careconnect.model.ehr.EhrEncounterRecord;
import com.careconnect.model.ehr.EhrReferenceValue;
import java.security.Principal;
import java.util.List;
import java.util.Map;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Provisional Condition/Encounter API pending approval of the unified OpenAPI contract. */
@RestController
@ConditionalOnProperty(
        prefix = "careconnect.cerner.clinical",
        name = "enabled",
        havingValue = "true")
@RequestMapping("/v1/api/cerner/patients/{patientId}")
public class CernerClinicalController {

    private final CernerConditionEncounterService service;
    private final CernerAccessPolicy policy;

    public CernerClinicalController(
            final CernerConditionEncounterService service, final CernerAccessPolicy policy) {
        this.service = service;
        this.policy = policy;
    }

    @GetMapping("/conditions")
    public ResponseEntity<?> conditions(
            @PathVariable final String patientId, final Principal principal) {
        final Long id = authorizedPatientId(patientId, principal);
        if (id == null) {
            return authorizationError(patientId, principal);
        }
        final List<ConditionView> records = service.synchronizeConditions(id).stream()
                .map(ConditionView::from)
                .toList();
        return ResponseEntity.ok(Map.of(
                "source", CernerProperties.SOURCE_ORACLE_HEALTH,
                "conditions", records));
    }

    @GetMapping("/encounters")
    public ResponseEntity<?> encounters(
            @PathVariable final String patientId, final Principal principal) {
        final Long id = authorizedPatientId(patientId, principal);
        if (id == null) {
            return authorizationError(patientId, principal);
        }
        final List<EncounterView> records = service.synchronizeEncounters(id).stream()
                .map(EncounterView::from)
                .toList();
        return ResponseEntity.ok(Map.of(
                "source", CernerProperties.SOURCE_ORACLE_HEALTH,
                "encounters", records));
    }

    private Long authorizedPatientId(final String patientId, final Principal principal) {
        if (principal == null) {
            return null;
        }
        try {
            final long id = Long.parseLong(patientId);
            return policy.canView(principal.getName(), id) ? id : null;
        } catch (NumberFormatException error) {
            return null;
        }
    }

    private ResponseEntity<Map<String, Object>> authorizationError(
            final String patientId, final Principal principal) {
        if (principal == null) {
            return error(HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "Login required",
                    "CARECONNECT", false);
        }
        try {
            Long.parseLong(patientId);
        } catch (NumberFormatException error) {
            return error(HttpStatus.BAD_REQUEST, "INVALID_PATIENT_ID", "Invalid patient id",
                    "CARECONNECT", false);
        }
        return error(HttpStatus.FORBIDDEN, "ACCESS_DENIED", "Access denied",
                "CARECONNECT", false);
    }

    @ExceptionHandler(UnknownPatientException.class)
    ResponseEntity<?> notFound() {
        return error(HttpStatus.NOT_FOUND, "PATIENT_NOT_FOUND", "Patient not found",
                "CARECONNECT", false);
    }

    @ExceptionHandler(CernerSourceException.class)
    ResponseEntity<?> source(final CernerSourceException error) {
        final HttpStatus status = "CERNER_AUTH_EXPIRED".equals(error.code())
                ? HttpStatus.CONFLICT : HttpStatus.BAD_GATEWAY;
        return error(status, error.code(), "Cerner source error",
                CernerProperties.SOURCE_ORACLE_HEALTH, error.retryable());
    }

    private static ResponseEntity<Map<String, Object>> error(
            final HttpStatus status,
            final String code,
            final String message,
            final String source,
            final boolean retryable) {
        return ResponseEntity.status(status).body(Map.of(
                "code", code,
                "message", message,
                "source", source,
                "retryable", retryable));
    }

    /** External view deliberately excludes database, patient, source, and raw-payload IDs. */
    public record ConditionView(
            String source,
            String sourceRecordId,
            String clinicalStatus,
            String verificationStatus,
            String severity,
            List<EhrCodeValue> categories,
            List<EhrCodeValue> conditionCodes,
            String conditionText,
            List<EhrCodeValue> bodySites,
            String onsetType,
            String onsetValue,
            String onsetPrecision,
            String abatementType,
            String abatementValue,
            String abatementPrecision,
            String recordedDate,
            String recordedDatePrecision,
            String encounterReference,
            String recorderReference,
            String recorderDisplay,
            boolean hiddenFromActiveList) {

        static ConditionView from(final EhrConditionRecord record) {
            return new ConditionView(
                    CernerProperties.SOURCE_ORACLE_HEALTH,
                    record.getExternalConditionId(),
                    record.getClinicalStatus(),
                    record.getVerificationStatus(),
                    record.getSeverity(),
                    record.getCategories(),
                    record.getConditionCodes(),
                    record.getConditionText(),
                    record.getBodySites(),
                    record.getOnsetType(),
                    record.getOnsetValue(),
                    record.getOnsetPrecision(),
                    record.getAbatementType(),
                    record.getAbatementValue(),
                    record.getAbatementPrecision(),
                    record.getRecordedDate(),
                    record.getRecordedDatePrecision(),
                    record.getEncounterReference(),
                    record.getRecorderReference(),
                    record.getRecorderDisplay(),
                    Boolean.TRUE.equals(record.getHiddenFromActiveList()));
        }
    }

    /** External view deliberately excludes database, patient, source, and raw-payload IDs. */
    public record EncounterView(
            String source,
            String sourceRecordId,
            String status,
            String classSystem,
            String classCode,
            String classDisplay,
            List<EhrCodeValue> encounterTypes,
            String periodStart,
            String periodStartPrecision,
            String periodEnd,
            String periodEndPrecision,
            List<EhrEncounterParticipantValue> participants,
            String serviceProviderReference,
            String serviceProviderDisplay,
            List<EhrReferenceValue> locations,
            List<EhrCodeValue> reasonCodes,
            List<EhrReferenceValue> diagnosisReferences,
            List<EhrReferenceValue> appointmentReferences) {

        static EncounterView from(final EhrEncounterRecord record) {
            return new EncounterView(
                    CernerProperties.SOURCE_ORACLE_HEALTH,
                    record.getExternalEncounterId(),
                    record.getStatus(),
                    record.getClassSystem(),
                    record.getClassCode(),
                    record.getClassDisplay(),
                    record.getEncounterTypes(),
                    record.getPeriodStart(),
                    record.getPeriodStartPrecision(),
                    record.getPeriodEnd(),
                    record.getPeriodEndPrecision(),
                    record.getParticipants(),
                    record.getServiceProviderReference(),
                    record.getServiceProviderDisplay(),
                    record.getLocations(),
                    record.getReasonCodes(),
                    record.getDiagnosisReferences(),
                    record.getAppointmentReferences());
        }
    }
}
