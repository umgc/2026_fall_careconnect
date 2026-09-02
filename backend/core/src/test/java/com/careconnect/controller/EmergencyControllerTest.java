package com.careconnect.controller;

import com.careconnect.service.VialOfLifePdfService;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EmergencyControllerTest {

    private static final String EMERGENCY_ID = "VIAL123456";
    private static final byte[] PDF_BYTES = {37, 80, 68, 70, 45, 49, 46, 52}; // %PDF-1.4

    // ── shared constants ──────────────────────────────────────────────────────
    @Mock
    private VialOfLifePdfService vialOfLifePdfService;
    @InjectMocks
    private EmergencyController controller;

    // ── GET /{emergencyId}.pdf ────────────────────────────────────────────────

    @Nested
    class GetEmergencyPdf {

        @Test
        void returns200_whenPdfGeneratedSuccessfully() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsPdfBytes_asBody() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isEqualTo(PDF_BYTES);
        }

        @Test
        void contentTypeIsApplicationPdf() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.APPLICATION_PDF);
        }

        @Test
        void contentDispositionIsInline_withEmergencyId() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            final String disposition = response.getHeaders().getFirst("Content-Disposition");
            assertThat(disposition)
                    .contains("inline")
                    .contains("vial-of-life-" + EMERGENCY_ID + ".pdf");
        }

        @Test
        void contentLengthMatchesPdfSize() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentLength()).isEqualTo((long) PDF_BYTES.length);
        }

        @Test
        void returns404_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("patient not found"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void returns500_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("unexpected failure"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }

        @Test
        void bodyIsNull_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("not found"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
        void bodyIsNull_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("failure"));

            final ResponseEntity<byte[]> response = controller.getEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
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
        void returns200_whenPdfGeneratedSuccessfully() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsPdfBytes_asBody() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isEqualTo(PDF_BYTES);
        }

        @Test
        void contentTypeIsApplicationPdf() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.APPLICATION_PDF);
        }

        @Test
        void contentDispositionIsAttachment_withEmergencyId() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            final String disposition = response.getHeaders().getFirst("Content-Disposition");
            assertThat(disposition)
                    .contains("attachment")
                    .contains("vial-of-life-" + EMERGENCY_ID + ".pdf");
        }

        @Test
        void contentDispositionIsNotInline() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            final String disposition = response.getHeaders().getFirst("Content-Disposition");
            assertThat(disposition).doesNotContain("inline");
        }

        @Test
        void contentLengthMatchesPdfSize() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getHeaders().getContentLength()).isEqualTo((long) PDF_BYTES.length);
        }

        @Test
        void returns404_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("patient not found"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void returns500_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("unexpected failure"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }

        @Test
        void bodyIsNull_whenServiceThrowsIllegalArgumentException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new IllegalArgumentException("not found"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
        void bodyIsNull_whenServiceThrowsGenericException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("failure"));

            final ResponseEntity<byte[]> response = controller.downloadEmergencyPdf(EMERGENCY_ID);

            assertThat(response.getBody()).isNull();
        }

        @Test
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
        void returns200() throws Exception {
            final ResponseEntity<String> response = controller.healthCheck();

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void bodyConfirmsServiceIsOperational() throws Exception {
            final ResponseEntity<String> response = controller.healthCheck();

            assertThat(response.getBody()).isEqualTo("Emergency PDF service is operational");
        }

        @Test
        void doesNotInteractWithPdfService() throws Exception {
            controller.healthCheck();

            verifyNoInteractions(vialOfLifePdfService);
        }
    }

    // ── GET /debug/{emergencyId} ──────────────────────────────────────────────

    @Nested
    class DebugPatientData {

        @Test
        void returns200_whenVialIdValidAndPdfGeneratedSuccessfully() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void bodyContainsSuccessAndByteCount_onSuccess() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getBody())
                    .contains("SUCCESS")
                    .contains(String.valueOf(PDF_BYTES.length) + " bytes");
        }

        @Test
        void returns400_whenEmergencyIdDoesNotStartWithVial() throws Exception {
            final ResponseEntity<String> response = controller.debugPatientData("NOTVALID999");

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void bodyDescribesInvalidFormat_whenPrefixIsWrong() throws Exception {
            final ResponseEntity<String> response = controller.debugPatientData("NOTVALID999");

            assertThat(response.getBody()).contains("Invalid emergency ID format");
        }

        @Test
        void returns400_whenSuffixAfterVialIsNotNumeric() throws Exception {
            // "VIALabcdef" → starts with VIAL but "abcdef" is not a Long
            final ResponseEntity<String> response = controller.debugPatientData("VIALabcdef");

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void bodyDescribesParseFailure_whenSuffixIsNotNumeric() throws Exception {
            final ResponseEntity<String> response = controller.debugPatientData("VIALabcdef");

            assertThat(response.getBody()).contains("Could not parse patient ID");
        }

        @Test
        void returns500_whenPdfGenerationThrowsException() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID))
                    .thenThrow(new RuntimeException("pdf generation error"));

            final ResponseEntity<String> response = controller.debugPatientData(EMERGENCY_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }

        @Test
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
        void callsServiceWithOriginalEmergencyId_whenVialPrefixPresent() throws Exception {
            when(vialOfLifePdfService.generateVialOfLifePdf(EMERGENCY_ID)).thenReturn(PDF_BYTES);

            controller.debugPatientData(EMERGENCY_ID);

            verify(vialOfLifePdfService).generateVialOfLifePdf(EMERGENCY_ID);
        }

        @Test
        void doesNotCallService_whenPrefixIsInvalid() throws Exception {
            controller.debugPatientData("BADPREFIX123");

            verifyNoInteractions(vialOfLifePdfService);
        }

        @Test
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
