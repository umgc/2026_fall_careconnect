package com.careconnect.controller;

import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.PatientService;
import com.careconnect.service.VialOfLifePdfService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link EmergencyController}, with the PDF service, the caller, the access check and the
 * patient lookup mocked.
 *
 * <p>Test Plan §3.22: TC-EMG-149…152 (PR #336 author), TC-EMG-153…189 (inherited, labels only) and
 * TC-EMG-190…196 (Testing Lead). Test IDs are permanent.
 */
@ExtendWith(MockitoExtension.class)
class EmergencyControllerTest {

    private static final String EMERGENCY_ID = "VIAL123456";
    private static final byte[] PDF_BYTES = {37, 80, 68, 70, 45, 49, 46, 52}; // %PDF-1.4

    // ── shared constants ──────────────────────────────────────────────────────
    @Mock
    private VialOfLifePdfService vialOfLifePdfService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @Mock
    private PatientService patientService;
    @InjectMocks
    private EmergencyController controller;

    private static final long PATIENT_RECORD = 123456L;
    private static final long PATIENT_USER = 900L;

    /**
     * The existing cases below test what the endpoints do once a caller is allowed. Allow them here:
     * patient record 123456 belongs to user 900, the caller is an administrator, and the access check
     * passes. InterimAccessFix covers the refusals.
     */
    @BeforeEach
    void allowedCaller() {
        final Patient patient = new Patient();
        patient.setId(PATIENT_RECORD);
        patient.setUser(User.builder().id(PATIENT_USER).build());
        lenient().when(patientService.getPatientById(PATIENT_RECORD)).thenReturn(patient);
        lenient().when(securityUtil.resolveCurrentUser()).thenReturn(User.builder().id(1L).role(Role.ADMIN).build());
    }

    // ── DEF-EMG-01 / DEF-EMG-03 interim fix ───────────────────────────────────

    @Nested
    class InterimAccessFix {

        @Test
        @DisplayName("TC-EMG-149: DEF-EMG-01 interim fix: a caller the access check refuses gets 404 from both PDF paths and nothing is generated")
        void pdfIs404_andNothingGenerated_whenCallerMayNotSeeThePatient() throws Exception {
            when(securityUtil.resolveCurrentUser()).thenReturn(User.builder().id(2L).role(Role.PATIENT).build());
            doThrow(new UnauthorizedException("refused")).when(authorizationService).requirePatientAccess(any(), eq(PATIENT_USER));

            assertThat(controller.getEmergencyPdf(EMERGENCY_ID).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            assertThat(controller.downloadEmergencyPdf(EMERGENCY_ID).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-150: DEF-EMG-01 interim fix: the access check is given the patient's user id, not the patient record id")
        void accessCheckGetsThePatientsUserId_notTheRecordId() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            controller.getEmergencyPdf(EMERGENCY_ID);

            verify(authorizationService).requirePatientAccess(any(), eq(PATIENT_USER));
        }

        @Test
        @DisplayName("TC-EMG-151: DEF-EMG-01 interim fix: a patient lookup that returns nothing is 404, like a refusal, and nothing is generated")
        void unknownPatientIs404_likeARefusal() throws Exception {
            assertThat(controller.getEmergencyPdf("VIAL999").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @Test
        @DisplayName("TC-EMG-152: DEF-EMG-03 interim fix: /debug/{id} is 404 for a non-admin and nothing is generated")
        void debugIs404_forANonAdmin() throws Exception {
            when(securityUtil.resolveCurrentUser()).thenReturn(User.builder().id(2L).role(Role.PATIENT).build());

            assertThat(controller.debugPatientData(EMERGENCY_ID).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            verify(vialOfLifePdfService, never()).generateVialOfLifePdf(anyString());
        }

        @ParameterizedTest(name = "{0}: DEF-EMG-01 interim fix: malformed ID \"{1}\" is 404 from both PDF paths, with no patient lookup, no access check and nothing generated")
        @CsvSource({
                "TC-EMG-190, ABC123",
                "TC-EMG-191, VIAL",
                "TC-EMG-192, VIALx1",
                "TC-EMG-193, vial123456"})
        void malformedIdIs404_beforeAnyLookup(final String id, final String emergencyId) throws Exception {
            assertThat(controller.getEmergencyPdf(emergencyId).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            assertThat(controller.downloadEmergencyPdf(emergencyId).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            verifyNoInteractions(patientService, authorizationService, vialOfLifePdfService);
        }

        @Test
        @DisplayName("TC-EMG-194: DEF-EMG-01 interim fix: an unknown patient, as the real PatientService reports it (AppException 404), is 404 from both PDF paths with no access check and nothing generated")
        void unknownPatientAppExceptionIs404() throws Exception {
            when(patientService.getPatientById(999L)).thenThrow(new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

            assertThat(controller.getEmergencyPdf("VIAL999").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            assertThat(controller.downloadEmergencyPdf("VIAL999").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            verifyNoInteractions(authorizationService, vialOfLifePdfService);
        }

        @Test
        @DisplayName("TC-EMG-195: DEF-EMG-01 interim fix: a patient record with no user account is 404 with no access check and nothing generated")
        void patientWithoutUserIs404() throws Exception {
            when(patientService.getPatientById(777L)).thenReturn(new Patient());

            assertThat(controller.getEmergencyPdf("VIAL777").getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            verifyNoInteractions(authorizationService, vialOfLifePdfService);
        }

        @Test
        @DisplayName("TC-EMG-196: DEF-EMG-03 interim fix: /debug/{id} is 404 when no caller is signed in, and nothing is generated")
        void debugIs404_withNoCaller() throws Exception {
            when(securityUtil.resolveCurrentUser()).thenReturn(null);

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            assertThat(response.getBody()).isNull();
            verifyNoInteractions(vialOfLifePdfService);
        }
    }

    // ── GET /{emergencyId}.pdf ────────────────────────────────────────────────

    @Nested
    class GetEmergencyPdf {

        @Test
        @DisplayName("TC-EMG-153: GET /{id}.pdf: an allowed caller gets 200")
        void returns200_whenPdfGeneratedSuccessfully() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        @DisplayName("TC-EMG-154: GET /{id}.pdf: the body is the generated PDF bytes")
        void returnsPdfBytes_asBody() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isEqualTo(PDF_BYTES);
        }

        @Test
        @DisplayName("TC-EMG-155: GET /{id}.pdf: Content-Type is application/pdf")
        void contentTypeIsApplicationPdf() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.APPLICATION_PDF);
        }

        @Test
        @DisplayName("TC-EMG-156: GET /{id}.pdf: Content-Disposition is inline and names vial-of-life-{id}.pdf")
        void contentDispositionIsInline_withEmergencyId() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            final String disposition = response.getHeaders().getFirst("Content-Disposition");
            assertThat(disposition)
                    .contains("inline")
                    .contains("vial-of-life-" + EMERGENCY_ID + ".pdf");
        }

        @Test
        @DisplayName("TC-EMG-157: GET /{id}.pdf: Content-Length equals the PDF size")
        void contentLengthMatchesPdfSize() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentLength()).isEqualTo((long) PDF_BYTES.length);
        }

        @Test
        @DisplayName("TC-EMG-158: GET /{id}.pdf: 404 when the PDF service reports no patient (IllegalArgumentException)")
        void returns404_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("patient not found"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        @DisplayName("TC-EMG-159: GET /{id}.pdf: 500 when the PDF service fails otherwise")
        void returns500_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("unexpected failure"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }

        @Test
        @DisplayName("TC-EMG-160: GET /{id}.pdf: no body with the 404")
        void bodyIsNull_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("not found"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
        @DisplayName("TC-EMG-161: GET /{id}.pdf: no body with the 500")
        void bodyIsNull_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("failure"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
        @DisplayName("TC-EMG-162: GET /{id}.pdf: the PDF service is called with the requested ID")
        void callsServiceWithCorrectEmergencyId() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            controller.getEmergencyPdf(EMERGENCY_ID);

            verify(vialOfLifePdfService).generateVialOfLifePdf(EMERGENCY_ID);
        }
    }

    // ── GET /download/{emergencyId}.pdf ──────────────────────────────────────

    @Nested
    class DownloadEmergencyPdf {

        @Test
        @DisplayName("TC-EMG-163: GET /download/{id}.pdf: an allowed caller gets 200")
        void returns200_whenPdfGeneratedSuccessfully() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        @DisplayName("TC-EMG-164: GET /download/{id}.pdf: the body is the generated PDF bytes")
        void returnsPdfBytes_asBody() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isEqualTo(PDF_BYTES);
        }

        @Test
        @DisplayName("TC-EMG-165: GET /download/{id}.pdf: Content-Type is application/pdf")
        void contentTypeIsApplicationPdf() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.APPLICATION_PDF);
        }

        @Test
        @DisplayName("TC-EMG-166: GET /download/{id}.pdf: Content-Disposition is attachment and names vial-of-life-{id}.pdf")
        void contentDispositionIsAttachment_withEmergencyId() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            final String disposition = response.getHeaders().getFirst("Content-Disposition");
            assertThat(disposition)
                    .contains("attachment")
                    .contains("vial-of-life-" + EMERGENCY_ID + ".pdf");
        }

        @Test
        @DisplayName("TC-EMG-167: GET /download/{id}.pdf: Content-Disposition is not inline")
        void contentDispositionIsNotInline() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            final String disposition = response.getHeaders().getFirst("Content-Disposition");
            assertThat(disposition).doesNotContain("inline");
        }

        @Test
        @DisplayName("TC-EMG-168: GET /download/{id}.pdf: Content-Length equals the PDF size")
        void contentLengthMatchesPdfSize() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentLength()).isEqualTo((long) PDF_BYTES.length);
        }

        @Test
        @DisplayName("TC-EMG-169: GET /download/{id}.pdf: 404 when the PDF service reports no patient (IllegalArgumentException)")
        void returns404_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("patient not found"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        @DisplayName("TC-EMG-170: GET /download/{id}.pdf: 500 when the PDF service fails otherwise")
        void returns500_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("unexpected failure"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }

        @Test
        @DisplayName("TC-EMG-171: GET /download/{id}.pdf: no body with the 404")
        void bodyIsNull_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("not found"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
        @DisplayName("TC-EMG-172: GET /download/{id}.pdf: no body with the 500")
        void bodyIsNull_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("failure"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
        @DisplayName("TC-EMG-173: GET /download/{id}.pdf: the PDF service is called with the requested ID")
        void callsServiceWithCorrectEmergencyId() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            controller.downloadEmergencyPdf(EMERGENCY_ID);

            verify(vialOfLifePdfService).generateVialOfLifePdf(EMERGENCY_ID);
        }
    }

    // ── GET /health ───────────────────────────────────────────────────────────

    @Nested
    class HealthCheck {

        @Test
        @DisplayName("TC-EMG-174: GET /health: 200")
        void returns200() throws Exception {
            final ResponseEntity<String> response = controller.healthCheck();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        @DisplayName("TC-EMG-175: GET /health: the body says the service is operational")
        void bodyConfirmsServiceIsOperational() throws Exception {
            final ResponseEntity<String> response = controller.healthCheck();

            assertThat(response.getBody()).isEqualTo("Emergency PDF service is operational");
        }

        @Test
        @DisplayName("TC-EMG-176: GET /health: no PDF is generated")
        void doesNotInteractWithPdfService() throws Exception {
            controller.healthCheck();

            verifyNoInteractions(vialOfLifePdfService);
        }
    }

    // ── GET /debug/{emergencyId} ──────────────────────────────────────────────

    @Nested
    class DebugPatientData {

        @Test
        @DisplayName("TC-EMG-177: GET /debug/{id}: an administrator gets 200 when the PDF can be generated")
        void returns200_whenVialIdValidAndPdfGeneratedSuccessfully() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        @DisplayName("TC-EMG-178: GET /debug/{id}: the body says SUCCESS with the byte count")
        void bodyContainsSuccessAndByteCount_onSuccess() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getBody())
                    .contains("SUCCESS")
                    .contains(String.valueOf(PDF_BYTES.length) + " bytes");
        }

        @Test
        @DisplayName("TC-EMG-179: GET /debug/{id}: 400 for an ID without the VIAL prefix")
        void returns400_whenEmergencyIdDoesNotStartWithVial() throws Exception {
            final ResponseEntity<String> response = controller.debugPatientData("NOTVALID999");

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        @DisplayName("TC-EMG-180: GET /debug/{id}: the 400 body says the format is invalid")
        void bodyDescribesInvalidFormat_whenPrefixIsWrong() throws Exception {
            final ResponseEntity<String> response = controller.debugPatientData("NOTVALID999");

            assertThat(response.getBody()).contains("Invalid emergency ID format");
        }

        @Test
        @DisplayName("TC-EMG-181: GET /debug/{id}: 400 for a non-numeric ID after VIAL")
        void returns400_whenSuffixAfterVialIsNotNumeric() throws Exception {
            // "VIALabcdef" → starts with VIAL but "abcdef" is not a Long
            final ResponseEntity<String> response = controller.debugPatientData("VIALabcdef");

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        @DisplayName("TC-EMG-182: GET /debug/{id}: the 400 body says the ID could not be parsed")
        void bodyDescribesParseFailure_whenSuffixIsNotNumeric() throws Exception {
            final ResponseEntity<String> response = controller.debugPatientData("VIALabcdef");

            assertThat(response.getBody()).contains("Could not parse patient ID");
        }

        @Test
        @DisplayName("TC-EMG-183: GET /debug/{id}: 500 when PDF generation fails")
        void returns500_whenPdfGenerationThrowsException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("pdf generation error"));

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }

        @Test
        @DisplayName("TC-EMG-184: GET /debug/{id}: the 500 body gives the administrator the exception class and message")
        void bodyContainsExceptionDetails_whenPdfGenerationThrows() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("pdf generation error"));

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getBody())
                    .contains("Error generating PDF")
                    .contains("RuntimeException")
                    .contains("pdf generation error");
        }

        @Test
        @DisplayName("TC-EMG-185: GET /debug/{id}: the PDF service is called with the requested ID")
        void callsServiceWithOriginalEmergencyId_whenVialPrefixPresent() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            controller.debugPatientData(EMERGENCY_ID);

            verify(vialOfLifePdfService).generateVialOfLifePdf(EMERGENCY_ID);
        }

        @Test
        @DisplayName("TC-EMG-186: GET /debug/{id}: no PDF is generated for a bad prefix")
        void doesNotCallService_whenPrefixIsInvalid() throws Exception {
            controller.debugPatientData("BADPREFIX123");

            verifyNoInteractions(vialOfLifePdfService);
        }

        @Test
        @DisplayName("TC-EMG-187: GET /debug/{id}: no PDF is generated for a non-numeric ID")
        void doesNotCallService_whenSuffixIsNotNumeric() throws Exception {
            controller.debugPatientData("VIALnotanumber");

            verifyNoInteractions(vialOfLifePdfService);
        }

        /**
         * Covers the outer catch block (lines 174-178).
         * null.startsWith("VIAL") throws NullPointerException, which is NOT a
         * NumberFormatException so it escapes the inner catch and is caught by
         * the outer catch, returning 500 with an "Unexpected error" body.
         */
        @Test
        @DisplayName("TC-EMG-188: GET /debug/{id}: a null ID reaches the outer catch: 500 \"Unexpected error\"")
        void returns500_whenNullEmergencyIdTriggersOuterCatch() throws Exception {
            final ResponseEntity<String> response = controller.debugPatientData(null);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
            assertThat(response.getBody())
                    .contains("Unexpected error")
                    .contains("NullPointerException");
        }

        /**
         * Covers the vialOfLifePdfService == null guard (lines 160-162).
         * Uses reflection to null-out the field after @InjectMocks has set it,
         * simulating a misconfigured Spring context.
         */
        @Test
        @DisplayName("TC-EMG-189: GET /debug/{id}: 500 \"VialOfLifePdfService is null\" when the service is missing")
        void returns500_withNullServiceMessage_whenServiceFieldIsNull()
                throws NoSuchFieldException, IllegalAccessException {
            final java.lang.reflect.Field field =
                    EmergencyController.class.getDeclaredField("vialOfLifePdfService");
            field.setAccessible(true);
            field.set(controller, null);

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
            assertThat(response.getBody()).isEqualTo("VialOfLifePdfService is null");
        }
    }
}
