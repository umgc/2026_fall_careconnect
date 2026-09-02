package com.careconnect.controller;

import com.careconnect.dto.chat.AiRequest;
import com.careconnect.dto.homecare.ExtractedFieldDto;
import com.careconnect.dto.homecare.HomeCareExtractionResponseDto;
import com.careconnect.model.homecare.HomeCareDocumentType;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.homecare.HomeCareLlmExtractionService;
import com.careconnect.service.invoice.TextractService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class HomeCareDocumentControllerTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    @Mock
    private TextractService textractService;
    @Mock
    private HomeCareLlmExtractionService llmExtractionService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @SuppressWarnings("unchecked")
    private HomeCareDocumentController controller(HomeCareLlmExtractionService llm) {
        ObjectProvider<HomeCareLlmExtractionService> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(llm);
        return new HomeCareDocumentController(
                textractService, provider, objectMapper, securityUtil, authorizationService);
    }

    private List<MultipartFile> validFiles() {
        return List.of(new MockMultipartFile(
                "files", "employment_application.pdf", "application/pdf", new byte[]{1, 2, 3}));
    }

    private void ocrReturns(String rawText) throws Exception {
        when(textractService.analyzeAndGetResult(anyList(), anyString()))
                .thenReturn(new AiRequest.AnalysisResult(rawText, "homecare-documents/abc.pdf"));
    }

    private HomeCareExtractionResponseDto body(ResponseEntity<?> response) {
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isInstanceOf(HomeCareExtractionResponseDto.class);
        return (HomeCareExtractionResponseDto) response.getBody();
    }

    // ─── Successful extraction: OCR → LLM → draft-field mapping ──────────────

    @Test
    void extract_success_mapsOcrAndLlmOutputToDraftFields() throws Exception {
        ocrReturns("Full Name: Jane Doe");
        when(llmExtractionService.extractDocumentData(
                eq(HomeCareDocumentType.EMPLOYMENT_APPLICATION), any()))
                .thenReturn("{\"fullName\":\"Jane Doe\",\"email\":\"jane@example.com\"}");

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "EMPLOYMENT_APPLICATION"));

        assertThat(payload.status).isEqualTo(HomeCareExtractionResponseDto.STATUS_PREFILLED);
        assertThat(payload.documentType).isEqualTo("EMPLOYMENT_APPLICATION");
        assertThat(payload.documentLink).isEqualTo("homecare-documents/abc.pdf");

        Map<String, ExtractedFieldDto> byKey = fieldsByKey(payload);
        assertThat(byKey.get("fullName").value).isEqualTo("Jane Doe");
        assertThat(byKey.get("email").value).isEqualTo("jane@example.com");
    }

    @Test
    void extract_prefilledValues_areMachineGeneratedAndEditable() throws Exception {
        ocrReturns("raw text");
        when(llmExtractionService.extractDocumentData(any(), any()))
                .thenReturn("{\"fullName\":\"Jane Doe\",\"phone\":\"555-0100\"}");

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "EMPLOYMENT_APPLICATION"));

        Map<String, ExtractedFieldDto> byKey = fieldsByKey(payload);

        // Every prefilled value is identified as machine-generated…
        assertThat(byKey.get("fullName").machineGenerated).isTrue();
        assertThat(byKey.get("phone").machineGenerated).isTrue();
        // …and every field, prefilled or not, remains editable.
        assertThat(payload.fields).allSatisfy(f -> assertThat(f.editable).isTrue());
    }

    @Test
    void extract_missingFields_comeBackBlankEditableAndHuman() throws Exception {
        ocrReturns("raw text");
        when(llmExtractionService.extractDocumentData(any(), any()))
                .thenReturn("{\"fullName\":\"Jane Doe\"}");

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "EMPLOYMENT_APPLICATION"));

        // The full schema is always returned, in schema order.
        assertThat(payload.fields).hasSize(
                HomeCareDocumentType.EMPLOYMENT_APPLICATION.getFieldSchema().size());

        ExtractedFieldDto email = fieldsByKey(payload).get("email");
        assertThat(email.value).isEmpty();
        assertThat(email.machineGenerated).isFalse();
        assertThat(email.editable).isTrue();
    }

    // ─── Schema enforcement ───────────────────────────────────────────────────

    @Test
    void extract_extraFieldsOutsideSchema_areRejected() throws Exception {
        ocrReturns("raw text");
        // LLM hallucinates invoice fields on a hiring form.
        when(llmExtractionService.extractDocumentData(any(), any()))
                .thenReturn("{\"fullName\":\"Jane Doe\",\"invoiceTotal\":941.50,"
                        + "\"provider\":{\"name\":\"Acme\"},\"invoiceNumber\":\"INV-1\"}");

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "EMPLOYMENT_APPLICATION"));

        assertThat(payload.fields)
                .extracting(f -> f.key)
                .containsExactlyElementsOf(
                        HomeCareDocumentType.EMPLOYMENT_APPLICATION.getFieldSchema().keySet())
                .doesNotContain("invoiceTotal", "invoiceNumber", "provider");
    }

    @Test
    void extract_nonScalarValues_areNotAcceptedIntoSchemaFields() throws Exception {
        ocrReturns("raw text");
        when(llmExtractionService.extractDocumentData(any(), any()))
                .thenReturn("{\"fullName\":{\"first\":\"Jane\",\"last\":\"Doe\"},\"phone\":\"555-0100\"}");

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "EMPLOYMENT_APPLICATION"));

        Map<String, ExtractedFieldDto> byKey = fieldsByKey(payload);
        assertThat(byKey.get("fullName").value).isEmpty();
        assertThat(byKey.get("fullName").machineGenerated).isFalse();
        assertThat(byKey.get("phone").value).isEqualTo("555-0100");
    }

    @Test
    void extract_documentTypeDeterminesSchema() throws Exception {
        ocrReturns("raw text");
        // Employment-form content extracted while CERTIFICATION is selected:
        // only certification schema fields may come back, all blank.
        when(llmExtractionService.extractDocumentData(
                eq(HomeCareDocumentType.CERTIFICATION), any()))
                .thenReturn("{\"fullName\":\"Jane Doe\",\"positionAppliedFor\":\"HHA\"}");

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "CERTIFICATION"));

        assertThat(payload.fields)
                .extracting(f -> f.key)
                .containsExactlyElementsOf(
                        HomeCareDocumentType.CERTIFICATION.getFieldSchema().keySet())
                .doesNotContain("fullName", "positionAppliedFor");

        // Nothing matched the schema, so the draft requires manual entry.
        assertThat(payload.status)
                .isEqualTo(HomeCareExtractionResponseDto.STATUS_MANUAL_ENTRY_REQUIRED);
    }

    // ─── Failure fallback ─────────────────────────────────────────────────────

    @Test
    void extract_ocrFailure_fallsBackToManualEntry() throws Exception {
        when(textractService.analyzeAndGetResult(anyList(), anyString()))
                .thenThrow(new RuntimeException("Textract job timed out"));

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "EMPLOYMENT_APPLICATION"));

        assertThat(payload.status)
                .isEqualTo(HomeCareExtractionResponseDto.STATUS_MANUAL_ENTRY_REQUIRED);
        assertThat(payload.message).containsIgnoringCase("manually");
        assertThat(payload.documentLink).isNull();
        // Full schema present, all blank and editable — no crash.
        assertThat(payload.fields).hasSize(
                HomeCareDocumentType.EMPLOYMENT_APPLICATION.getFieldSchema().size());
        assertThat(payload.fields).allSatisfy(f -> {
            assertThat(f.value).isEmpty();
            assertThat(f.machineGenerated).isFalse();
            assertThat(f.editable).isTrue();
        });
    }

    @Test
    void extract_llmFailure_fallsBackToManualEntry() throws Exception {
        ocrReturns("valid OCR text");
        when(llmExtractionService.extractDocumentData(any(), any()))
                .thenThrow(new RuntimeException("Bedrock unavailable"));

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "TAX_FORM"));

        assertThat(payload.status)
                .isEqualTo(HomeCareExtractionResponseDto.STATUS_MANUAL_ENTRY_REQUIRED);
        // The upload succeeded, so the source document link is preserved.
        assertThat(payload.documentLink).isEqualTo("homecare-documents/abc.pdf");
        assertThat(payload.fields).allSatisfy(f -> assertThat(f.value).isEmpty());
    }

    @Test
    void extract_malformedLlmJson_fallsBackToManualEntry() throws Exception {
        ocrReturns("valid OCR text");
        when(llmExtractionService.extractDocumentData(any(), any()))
                .thenReturn("Sorry, I could not process this document.");

        HomeCareExtractionResponseDto payload = body(
                controller(llmExtractionService).extract(validFiles(), "WORK_AUTHORIZATION"));

        assertThat(payload.status)
                .isEqualTo(HomeCareExtractionResponseDto.STATUS_MANUAL_ENTRY_REQUIRED);
        assertThat(payload.fields).hasSize(
                HomeCareDocumentType.WORK_AUTHORIZATION.getFieldSchema().size());
    }

    @Test
    void extract_llmNotEnabled_fallsBackToManualEntry() throws Exception {
        ocrReturns("valid OCR text");

        HomeCareExtractionResponseDto payload = body(
                controller(null).extract(validFiles(), "EMPLOYMENT_APPLICATION"));

        assertThat(payload.status)
                .isEqualTo(HomeCareExtractionResponseDto.STATUS_MANUAL_ENTRY_REQUIRED);
        assertThat(payload.documentLink).isEqualTo("homecare-documents/abc.pdf");
    }

    // ─── Input validation ─────────────────────────────────────────────────────

    @Test
    void extract_unknownDocumentType_returnsBadRequest() throws Exception {
        ResponseEntity<?> response =
                controller(llmExtractionService).extract(validFiles(), "MEDICAL_INVOICE");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(String.valueOf(response.getBody())).contains("MEDICAL_INVOICE");
    }

    @Test
    void extract_emptyFileList_returnsBadRequest() throws Exception {
        ResponseEntity<?> response =
                controller(llmExtractionService).extract(List.of(), "EMPLOYMENT_APPLICATION");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void extract_allEmptyFiles_returnsBadRequest() throws Exception {
        List<MultipartFile> empty = List.of(new MockMultipartFile(
                "files", "empty.pdf", "application/pdf", new byte[0]));

        ResponseEntity<?> response =
                controller(llmExtractionService).extract(empty, "EMPLOYMENT_APPLICATION");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // ─── Document type listing ────────────────────────────────────────────────

    @Test
    void listDocumentTypes_returnsEveryTypeWithItsSchema() {
        ResponseEntity<List<Map<String, Object>>> response =
                controller(llmExtractionService).listDocumentTypes();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        List<Map<String, Object>> types = response.getBody();
        assertThat(types).isNotNull();
        assertThat(types).hasSize(HomeCareDocumentType.values().length);
        assertThat(types)
                .extracting(t -> t.get("type"))
                .containsExactlyInAnyOrder("EMPLOYMENT_APPLICATION", "CERTIFICATION",
                        "TAX_FORM", "WORK_AUTHORIZATION");
        assertThat(types).allSatisfy(t -> {
            assertThat((String) t.get("displayName")).isNotBlank();
            assertThat((List<?>) t.get("fields")).isNotEmpty();
        });
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private Map<String, ExtractedFieldDto> fieldsByKey(HomeCareExtractionResponseDto payload) {
        return payload.fields.stream()
                .collect(java.util.stream.Collectors.toMap(f -> f.key, f -> f));
    }
}
