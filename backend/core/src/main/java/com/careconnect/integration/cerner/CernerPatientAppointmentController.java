package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.integration.cerner.CernerAllergyService.UnknownPatientException;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrSourceIdentity;
import java.security.Principal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Provisional read-only Patient/Appointment API pending the unified OpenAPI contract. */
@RestController
@ConditionalOnProperty(
        prefix = "careconnect.cerner.patient-appointment",
        name = "enabled",
        havingValue = "true")
@RequestMapping("/v1/api/cerner/patients/{patientId}")
public class CernerPatientAppointmentController {

    private final CernerPatientAppointmentService service;
    private final CernerAccessPolicy policy;

    public CernerPatientAppointmentController(
            final CernerPatientAppointmentService service,
            final CernerAccessPolicy policy) {
        this.service = service;
        this.policy = policy;
    }

    /** Retrieves the authorized Cerner Patient and returns its normalized source identity. */
    @GetMapping
    public ResponseEntity<?> patient(
            @PathVariable final String patientId, final Principal principal) {
        final Long id = authorizedPatientId(patientId, principal);
        if (id == null) {
            return authorizationError(patientId, principal);
        }
        final var synchronizedPatient = service.synchronizePatientWithSourceRecord(id);
        return ResponseEntity.ok(Map.of(
                "source", CernerProperties.SOURCE_ORACLE_HEALTH,
                "patient", PatientView.from(synchronizedPatient)));
    }

    /** Retrieves provisional and scheduled appointments inside one required bounded interval. */
    @GetMapping("/appointments")
    public ResponseEntity<?> appointments(
            @PathVariable final String patientId,
            @RequestParam
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME)
            final Instant start,
            @RequestParam
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME)
            final Instant end,
            final Principal principal) {
        final Long id = authorizedPatientId(patientId, principal);
        if (id == null) {
            return authorizationError(patientId, principal);
        }
        if (!start.isBefore(end)) {
            return error(
                    HttpStatus.BAD_REQUEST,
                    "INVALID_DATE_RANGE",
                    "Appointment start must be before end",
                    "CARECONNECT",
                    false);
        }
        final List<AppointmentView> records = service
                .synchronizeAppointments(id, start, end)
                .stream()
                .map(AppointmentView::from)
                .toList();
        return ResponseEntity.ok(Map.of(
                "source", CernerProperties.SOURCE_ORACLE_HEALTH,
                "appointments", records));
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
            return error(
                    HttpStatus.UNAUTHORIZED,
                    "UNAUTHENTICATED",
                    "Login required",
                    "CARECONNECT",
                    false);
        }
        try {
            Long.parseLong(patientId);
        } catch (NumberFormatException error) {
            return error(
                    HttpStatus.BAD_REQUEST,
                    "INVALID_PATIENT_ID",
                    "Invalid patient id",
                    "CARECONNECT",
                    false);
        }
        return error(
                HttpStatus.FORBIDDEN,
                "ACCESS_DENIED",
                "Access denied",
                "CARECONNECT",
                false);
    }

    @ExceptionHandler(UnknownPatientException.class)
    ResponseEntity<?> notFound() {
        return error(
                HttpStatus.NOT_FOUND,
                "PATIENT_NOT_FOUND",
                "Patient not found",
                "CARECONNECT",
                false);
    }

    @ExceptionHandler(CernerSourceException.class)
    ResponseEntity<?> source(final CernerSourceException sourceError) {
        final HttpStatus status = "CERNER_AUTH_EXPIRED".equals(sourceError.code())
                ? HttpStatus.CONFLICT : HttpStatus.BAD_GATEWAY;
        return error(
                status,
                sourceError.code(),
                "Cerner source error",
                CernerProperties.SOURCE_ORACLE_HEALTH,
                sourceError.retryable());
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

    /** External view deliberately excludes database and raw-payload identifiers. */
    public record PatientView(
            String source,
            String sourceRecordId,
            String sourceUpdatedAt,
            String givenName,
            String familyName,
            String dateOfBirth,
            String phone,
            String email,
            String addressLine1,
            String addressLine2,
            String city,
            String state,
            String postalCode,
            String gender,
            String memberId,
            String managingOrg,
            String language) {

        static PatientView from(
                final CernerPatientAppointmentService.PatientSynchronization result) {
            final EhrSourceIdentity identity = result.identity();
            return new PatientView(
                    CernerProperties.SOURCE_ORACLE_HEALTH,
                    result.sourceRecordId(),
                    identity.getSourceUpdatedAt().toString(),
                    identity.getGivenName(),
                    identity.getFamilyName(),
                    text(identity.getDateOfBirth()),
                    identity.getPhone(),
                    identity.getEmail(),
                    identity.getAddressLine1(),
                    identity.getAddressLine2(),
                    identity.getCity(),
                    identity.getState(),
                    identity.getPostalCode(),
                    identity.getGender(),
                    identity.getMemberId(),
                    identity.getManagingOrg(),
                    identity.getLanguage());
        }
    }

    /** External view deliberately excludes database and raw-payload identifiers. */
    public record AppointmentView(
            String source,
            String sourceRecordId,
            String status,
            String startTime,
            String endTime,
            String providerName,
            String location,
            String serviceType,
            String reason,
            String sourceCreatedAt,
            String sourceUpdatedAt) {

        static AppointmentView from(final EhrAppointmentRecord record) {
            return new AppointmentView(
                    CernerProperties.SOURCE_ORACLE_HEALTH,
                    record.getExternalAppointmentId(),
                    record.getStatus(),
                    utc(record.getStartTime()),
                    utc(record.getEndTime()),
                    record.getProviderName(),
                    record.getLocation(),
                    record.getServiceType(),
                    record.getReason(),
                    utc(record.getSourceCreatedAt()),
                    utc(record.getSourceUpdatedAt()));
        }
    }

    private static String text(final LocalDate value) {
        return value == null ? null : value.toString();
    }

    private static String utc(final LocalDateTime value) {
        return value == null ? null : value.atOffset(ZoneOffset.UTC).toString();
    }
}
