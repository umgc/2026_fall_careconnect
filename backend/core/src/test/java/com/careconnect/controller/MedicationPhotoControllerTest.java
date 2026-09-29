package com.careconnect.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.multipart.MultipartFile;

import com.careconnect.dto.MedicationPhotoExtractedField;
import com.careconnect.dto.MedicationPhotoExtractionResponse;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.MedicationPhotoExtractionService;
import com.careconnect.service.MedicationService;
import com.careconnect.testsupport.fixtures.MedicationPhotoFixtures;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * F-01 extract-photo endpoint (TC-MED-PHOTO-021..032).
 *
 * <p>
 * Controller-level unit tests (same style as MedicationControllerTest): the
 * extraction service, SecurityUtil, AuthorizationService and MedicationService
 * are mocks, so no AWS, DB or Spring context is involved. Route:
 * POST /v3/api/patients/{patientId}/medications/extract-photo. This deviates
 * from the TDD example path /v1/api/medications/extract-photo by lead decision
 * (same auth as addMedication).
 * </p>
 */
@ExtendWith(MockitoExtension.class)
class MedicationPhotoControllerTest {

    private static final Long PATIENT_ID = 1L;

    @Mock
    private MedicationService medicationService;
    @Mock
    private MedicationPhotoExtractionService photoService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private MedicationController controller;

    private final User user = mock(User.class);

    private MockMultipartFile image(String contentType, byte[] bytes) {
        return new MockMultipartFile("image", "label.jpg", contentType, bytes);
    }

    private void authorised() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user);
    }

    private MedicationPhotoExtractionResponse prefilled() {
        final MedicationPhotoExtractionResponse r = new MedicationPhotoExtractionResponse();
        r.status = MedicationPhotoExtractionResponse.STATUS_PREFILLED;
        r.message = "ok";
        r.fields.add(new MedicationPhotoExtractedField("medicationName", "Medication Name", "Lisinopril", true));
        return r;
    }

    @Test
    @DisplayName("TC-MED-PHOTO-021: JPEG upload returns 200 and the service result, bytes passed through")
    void jpeg_returnsServiceResult() throws Exception {
        authorised();
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();
        final MedicationPhotoExtractionResponse expected = prefilled();
        when(photoService.extract(bytes)).thenReturn(expected);

        final ResponseEntity<?> resp = controller.extractMedicationPhoto(PATIENT_ID, image("image/jpeg", bytes));

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(resp.getBody()).isSameAs(expected);
        verify(authorizationService).requirePatientAccess(user, PATIENT_ID);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-022: PNG upload is accepted")
    void png_accepted() throws Exception {
        authorised();
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();
        when(photoService.extract(bytes)).thenReturn(prefilled());

        assertThat(controller.extractMedicationPhoto(PATIENT_ID, image("image/png", bytes)).getStatusCode())
                .isEqualTo(HttpStatus.OK);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-023: access denied -> UnauthorizedException, extraction never runs")
    void accessDenied_noExtraction() throws Exception {
        authorised();
        doThrow(new UnauthorizedException("no access"))
                .when(authorizationService).requirePatientAccess(user, PATIENT_ID);

        assertThatThrownBy(() -> controller.extractMedicationPhoto(
                PATIENT_ID, image("image/jpeg", MedicationPhotoFixtures.imageBytes())))
                .isInstanceOf(UnauthorizedException.class);

        verifyNoInteractions(photoService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-024: unresolved current user propagates and extraction never runs")
    void noCurrentUser_noExtraction() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenThrow(new IllegalStateException("no auth"));

        assertThatThrownBy(() -> controller.extractMedicationPhoto(
                PATIENT_ID, image("image/jpeg", MedicationPhotoFixtures.imageBytes())))
                .isInstanceOf(IllegalStateException.class);

        verifyNoInteractions(photoService);
        verifyNoInteractions(authorizationService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-025: empty file -> 400 and no extraction")
    void emptyFile_400() throws Exception {
        authorised();

        final ResponseEntity<?> resp = controller.extractMedicationPhoto(PATIENT_ID, image("image/jpeg", new byte[0]));

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(((Map<?, ?>) resp.getBody()).get("message")).isNotNull();
        verifyNoInteractions(photoService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-026: null image part -> 400 and no extraction")
    void nullImage_400() throws Exception {
        authorised();

        assertThat(controller.extractMedicationPhoto(PATIENT_ID, null).getStatusCode())
                .isEqualTo(HttpStatus.BAD_REQUEST);
        verifyNoInteractions(photoService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-027: non-JPEG/PNG or missing content type -> 400 and no extraction")
    void wrongContentType_400() throws Exception {
        authorised();
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();

        for (final String type : new String[] {"image/gif", "application/pdf", "text/plain", null}) {
            final ResponseEntity<?> resp = controller.extractMedicationPhoto(PATIENT_ID, image(type, bytes));
            assertThat(resp.getStatusCode()).as("content type %s", type).isEqualTo(HttpStatus.BAD_REQUEST);
        }
        verifyNoInteractions(photoService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-028: over-10MB file -> in-controller 400 (unit level only; prod is rejected earlier by the servlet limit)")
    void overTenMb_controllerLevel400() throws Exception {
        authorised();
        final MultipartFile big = mock(MultipartFile.class);
        when(big.isEmpty()).thenReturn(false);
        when(big.getSize()).thenReturn(10L * 1024 * 1024 + 1);

        final ResponseEntity<?> resp = controller.extractMedicationPhoto(PATIENT_ID, big);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        verify(big, never()).getBytes();
        verifyNoInteractions(photoService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-029: unreadable upload (IOException) -> 400, no bytes in body")
    void ioException_400() throws Exception {
        authorised();
        final MultipartFile bad = mock(MultipartFile.class);
        when(bad.isEmpty()).thenReturn(false);
        when(bad.getSize()).thenReturn(10L);
        when(bad.getContentType()).thenReturn("image/jpeg");
        when(bad.getBytes()).thenThrow(new IOException("disk"));

        final ResponseEntity<?> resp = controller.extractMedicationPhoto(PATIENT_ID, bad);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        verifyNoInteractions(photoService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-030: 400 bodies never contain image content")
    void errorBodies_haveNoImageContent() throws Exception {
        authorised();
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();
        final ObjectMapper om = new ObjectMapper();

        final String wrongType = om.writeValueAsString(
                controller.extractMedicationPhoto(PATIENT_ID, image("image/gif", bytes)).getBody());
        final String empty = om.writeValueAsString(
                controller.extractMedicationPhoto(PATIENT_ID, image("image/jpeg", new byte[0])).getBody());

        for (final String json : new String[] {wrongType, empty}) {
            MedicationPhotoFixtures.imageLeakNeedles().forEach(n -> assertThat(json).doesNotContain(n));
            assertThat(new String(json.getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8))
                    .contains("message");
        }
    }

    @Test
    @DisplayName("TC-MED-PHOTO-031: extraction never persists (MedicationService untouched) and service fallback stays 200")
    void extraction_persistsNothing_fallbackIs200() throws Exception {
        authorised();
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();
        final MedicationPhotoExtractionResponse fallback = new MedicationPhotoExtractionResponse();
        fallback.status = MedicationPhotoExtractionResponse.STATUS_MANUAL_ENTRY_REQUIRED;
        fallback.message = "The photo could not be read.";
        when(photoService.extract(bytes)).thenReturn(fallback);

        final ResponseEntity<?> resp = controller.extractMedicationPhoto(PATIENT_ID, image("image/jpeg", bytes));

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        verifyNoInteractions(medicationService);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-032: wire JSON has status, message and fields[key,label,value,machineGenerated]")
    void wireContract() throws Exception {
        final String json = new ObjectMapper().writeValueAsString(prefilled());

        assertThat(json).contains("\"status\":\"PREFILLED\"", "\"message\"", "\"fields\":[",
                "\"key\":\"medicationName\"", "\"label\"", "\"value\":\"Lisinopril\"", "\"machineGenerated\":true");
    }
}
