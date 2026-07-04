package com.careconnect.controller;

import com.careconnect.dto.chat.AiRequest;
import com.careconnect.dto.homecare.ExtractedFieldDto;
import com.careconnect.dto.homecare.HomeCareExtractionResponseDto;
import com.careconnect.model.User;
import com.careconnect.model.homecare.HomeCareDocumentType;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.homecare.HomeCareLlmExtractionService;
import com.careconnect.service.invoice.TextractService;
import com.careconnect.util.JsonSanitizer;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Home Care Document Digitization.
 *
 * Reuses the invoice Textract + LLM extraction pipeline to prefill structured
 * home-care onboarding document fields for human review. Prefilled values are
 * flagged as machine-generated and remain editable; any OCR or LLM failure
 * falls back cleanly to a manual-entry response instead of an error.
 */
@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = false)
@RestController
@RequestMapping("/v1/api/homecare-documents")
@Slf4j
public class HomeCareDocumentController {

    private static final String S3_KEY_PREFIX = "homecare-documents/";

    private final TextractService textractService;
    @org.springframework.lang.Nullable
    private final HomeCareLlmExtractionService llmExtractionService;
    private final ObjectMapper objectMapper;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    public HomeCareDocumentController(
            TextractService textractService,
            ObjectProvider<HomeCareLlmExtractionService> llmExtractionServiceProvider,
            ObjectMapper objectMapper,
            SecurityUtil securityUtil,
            AuthorizationService authorizationService
    ) {
        this.textractService = textractService;
        this.llmExtractionService = llmExtractionServiceProvider.getIfAvailable();
        this.objectMapper = objectMapper;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
    }

    // ==============================
    // Document type schemas
    // ==============================

    @GetMapping("/types")
    public ResponseEntity<List<Map<String, Object>>> listDocumentTypes() {
        List<Map<String, Object>> types = new ArrayList<>();
        for (HomeCareDocumentType type : HomeCareDocumentType.values()) {
            Map<String, Object> entry = new HashMap<>();
            entry.put("type", type.name());
            entry.put("displayName", type.getDisplayName());

            List<Map<String, String>> fields = new ArrayList<>();
            type.getFieldSchema().forEach((key, label) ->
                    fields.add(Map.of("key", key, "label", label)));
            entry.put("fields", fields);

            types.add(entry);
        }
        return ResponseEntity.ok(types);
    }

    // ==============================
    // OCR + LLM Extraction
    // ==============================

    @PostMapping(value = "/extract", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> extract(
            @RequestParam("files") List<MultipartFile> files,
            @RequestParam("documentType") String documentTypeRaw
    ) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();

        // Enforce caregiver/admin role when a user is resolved.
        // SecurityConfig requires authentication for this endpoint, so
        // currentUser will be non-null for all authenticated callers.
        if (currentUser != null) {
            authorizationService.requireAdminOrCaregiver(currentUser);
        }

        Optional<HomeCareDocumentType> typeOpt = HomeCareDocumentType.fromString(documentTypeRaw);
        if (typeOpt.isEmpty()) {
            return ResponseEntity.badRequest()
                    .body("Unknown documentType: " + documentTypeRaw);
        }
        HomeCareDocumentType type = typeOpt.get();

        if (isFileListInvalid(files)) {
            return ResponseEntity.badRequest().body("Please provide at least one valid file.");
        }

        log.info("Received home-care document for OCR: {} (type: {})",
                files.get(0).getOriginalFilename(), type.name());

        // Step 1: Textract OCR
        AiRequest.AnalysisResult ocrResult;
        try {
            ocrResult = textractService.analyzeAndGetResult(files, S3_KEY_PREFIX);
        } catch (Exception e) {
            log.error("Textract OCR failed for home-care document, falling back to manual entry", e);
            return ResponseEntity.ok(manualEntryFallback(type, null,
                    "Automatic text extraction failed. Please enter the fields manually."));
        }

        // Step 2: LLM extraction restricted to this document type's schema
        if (llmExtractionService == null) {
            return ResponseEntity.ok(manualEntryFallback(type, ocrResult.s3Key,
                    "AI extraction is not enabled. Please enter the fields manually."));
        }

        try {
            String aiResult = llmExtractionService.extractDocumentData(type, ocrResult.rawText);
            String sanitizedJson = JsonSanitizer.extractFirstJsonObject(aiResult);
            if (sanitizedJson == null) {
                throw new IllegalStateException("LLM response contained no JSON object");
            }

            JsonNode root = objectMapper.readTree(sanitizedJson);
            if (!root.isObject()) {
                throw new IllegalStateException("LLM response was not a JSON object");
            }

            HomeCareExtractionResponseDto payload =
                    buildPrefilledResponse(type, root, ocrResult.s3Key);
            return ResponseEntity.ok(payload);

        } catch (Exception e) {
            log.error("LLM extraction failed for home-care document, falling back to manual entry", e);
            return ResponseEntity.ok(manualEntryFallback(type, ocrResult.s3Key,
                    "AI extraction failed. Please enter the fields manually."));
        }
    }

    // ==============================
    // Helpers
    // ==============================

    /**
     * Builds the draft response, keeping only fields present in the document
     * type's schema. Keys the LLM invented are dropped; schema keys the LLM
     * omitted come back blank for manual entry.
     */
    private HomeCareExtractionResponseDto buildPrefilledResponse(
            HomeCareDocumentType type, JsonNode extracted, String s3Key) {

        HomeCareExtractionResponseDto payload = newResponse(type, s3Key);

        int prefilledCount = 0;
        for (Map.Entry<String, String> field : type.getFieldSchema().entrySet()) {
            JsonNode node = extracted.get(field.getKey());
            // Only accept scalar values; objects/arrays are outside the schema.
            String value = node != null && node.isValueNode() ? node.asText().trim() : "";
            boolean machineGenerated = !value.isEmpty();
            if (machineGenerated) {
                prefilledCount++;
            }
            payload.fields.add(new ExtractedFieldDto(field.getKey(), field.getValue(), value, machineGenerated));
        }

        if (prefilledCount > 0) {
            payload.status = HomeCareExtractionResponseDto.STATUS_PREFILLED;
            payload.message = String.format(
                    "%d of %d fields were prefilled by AI. Review and edit before saving.",
                    prefilledCount, type.getFieldSchema().size());
        } else {
            payload.status = HomeCareExtractionResponseDto.STATUS_MANUAL_ENTRY_REQUIRED;
            payload.message = "No fields could be extracted from the document. Please enter them manually.";
        }
        return payload;
    }

    private HomeCareExtractionResponseDto manualEntryFallback(
            HomeCareDocumentType type, String s3Key, String message) {

        HomeCareExtractionResponseDto payload = newResponse(type, s3Key);
        payload.status = HomeCareExtractionResponseDto.STATUS_MANUAL_ENTRY_REQUIRED;
        payload.message = message;
        type.getFieldSchema().forEach((key, label) ->
                payload.fields.add(new ExtractedFieldDto(key, label, "", false)));
        return payload;
    }

    private HomeCareExtractionResponseDto newResponse(HomeCareDocumentType type, String s3Key) {
        HomeCareExtractionResponseDto payload = new HomeCareExtractionResponseDto();
        payload.documentType = type.name();
        payload.documentTypeDisplayName = type.getDisplayName();
        payload.documentLink = s3Key;
        return payload;
    }

    private boolean isFileListInvalid(List<MultipartFile> files) {
        return files == null
                || files.isEmpty()
                || files.stream().allMatch(MultipartFile::isEmpty);
    }
}
