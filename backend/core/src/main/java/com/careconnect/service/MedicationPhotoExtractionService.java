package com.careconnect.service;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.MedicationPhotoExtractedField;
import com.careconnect.dto.MedicationPhotoExtractionResponse;
import com.careconnect.model.Medication;
import com.careconnect.util.JsonSanitizer;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.Block;
import software.amazon.awssdk.services.textract.model.BlockType;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextRequest;
import software.amazon.awssdk.services.textract.model.Document;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Medication label photo to draft medication fields (F-01, ADR-05).
 * <p>
 * OCR follows MailpieceOcrService's in-memory Textract pattern: the image bytes
 * go straight to DetectDocumentText and are never logged, stored, or sent to S3.
 * The OCR text is then structured by the configured LLM, the same way
 * HomeCareLlmExtractionService does. Any failure returns a blank
 * manual-entry response; nothing is retried.
 */
@Service
@Slf4j
public class MedicationPhotoExtractionService {

    static final String FIELD_NAME = "medicationName";
    static final String FIELD_DOSAGE = "dosage";
    static final String FIELD_FREQUENCY = "frequency";
    static final String FIELD_MEDICATION_TYPE = "medicationType";

    private static final int REJECTED_TYPE_LOG_LIMIT = 40;

    private static final Map<String, String> FIELD_LABELS = new LinkedHashMap<>();

    static {
        FIELD_LABELS.put(FIELD_NAME, "Medication Name");
        FIELD_LABELS.put(FIELD_DOSAGE, "Dosage");
        FIELD_LABELS.put(FIELD_FREQUENCY, "Frequency");
        FIELD_LABELS.put(FIELD_MEDICATION_TYPE, "Medication Type");
    }

    private final TextractClient textractClient;
    private final AIServiceFactory aiServiceFactory;
    private final ObjectMapper objectMapper;

    public MedicationPhotoExtractionService(
            ObjectProvider<TextractClient> textractClientProvider,
            AIServiceFactory aiServiceFactory,
            ObjectMapper objectMapper
    ) {
        this.textractClient = textractClientProvider.getIfAvailable();
        this.aiServiceFactory = aiServiceFactory;
        this.objectMapper = objectMapper;
    }

    public MedicationPhotoExtractionResponse extract(byte[] imageBytes) {
        if (textractClient == null) {
            log.warn("Medication photo OCR unavailable (careconnect.aws.enabled is off), falling back to manual entry");
            return manualEntry("Photo reading is not available. Please enter the medication manually.");
        }

        String labelText;
        try {
            labelText = detectText(imageBytes);
        } catch (Exception e) {
            log.warn("Medication photo OCR failed, falling back to manual entry: {}: {}",
                    e.getClass().getSimpleName(), e.getMessage());
            return manualEntry("The photo could not be read. Please enter the medication manually.");
        }
        if (labelText.isBlank()) {
            log.warn("Medication photo OCR found no text, falling back to manual entry");
            return manualEntry("No text was found in the photo. Please enter the medication manually.");
        }

        JsonNode extracted;
        try {
            extracted = structureWithLlm(labelText);
        } catch (Exception e) {
            // Parse errors can quote the LLM output, which repeats label text, so only the cause type is logged.
            log.warn("Medication photo LLM structuring failed, falling back to manual entry: {}",
                    e.getClass().getSimpleName());
            return manualEntry("The photo could not be read. Please enter the medication manually.");
        }

        return buildPrefilledResponse(extracted);
    }

    private String detectText(byte[] imageBytes) {
        List<Block> blocks = textractClient.detectDocumentText(
                DetectDocumentTextRequest.builder()
                        .document(Document.builder()
                                .bytes(SdkBytes.fromByteArray(imageBytes))
                                .build())
                        .build()
        ).blocks();

        return blocks.stream()
                .filter(b -> b.blockType() == BlockType.LINE)
                .map(Block::text)
                .filter(text -> text != null && !text.isBlank())
                .collect(Collectors.joining("\n"));
    }

    private JsonNode structureWithLlm(String labelText) throws Exception {
        String prompt = """
                You are a medication label extraction engine.

                Extract data from a medication label and return ONLY valid JSON.

                Do NOT explain anything.
                Do NOT return text.
                Do NOT use markdown.
                Do NOT add fields that are not in the format below.

                Return EXACTLY this format:

                {"medicationName": "", "dosage": "", "frequency": "", "medicationType": ""}

                medicationType must be one of: %s.
                Use an empty string "" for any value that is not present on the label.
                Only return JSON.

                Label:
                %s
                """.formatted(String.join(", ", medicationTypeNames()), labelText);

        ChatRequest request = new ChatRequest();
        request.setMessage(prompt);

        String aiResult = aiServiceFactory.getService().processChat(request).getAiResponse();
        String json = JsonSanitizer.extractFirstJsonObject(aiResult);
        if (json == null) {
            throw new IllegalStateException("LLM response contained no JSON object");
        }
        JsonNode root = objectMapper.readTree(json);
        if (!root.isObject()) {
            throw new IllegalStateException("LLM response was not a JSON object");
        }
        return root;
    }

    private MedicationPhotoExtractionResponse buildPrefilledResponse(JsonNode extracted) {
        MedicationPhotoExtractionResponse response = new MedicationPhotoExtractionResponse();
        List<String> unmapped = new ArrayList<>();

        for (Map.Entry<String, String> field : FIELD_LABELS.entrySet()) {
            JsonNode node = extracted.get(field.getKey());
            String value = node != null && node.isValueNode() ? node.asText().trim() : "";
            if (FIELD_MEDICATION_TYPE.equals(field.getKey())) {
                value = toMedicationType(value);
            }
            boolean machineGenerated = !value.isEmpty();
            if (!machineGenerated) {
                unmapped.add(field.getKey());
            }
            response.fields.add(new MedicationPhotoExtractedField(field.getKey(), field.getValue(), value, machineGenerated));
        }

        if (!unmapped.isEmpty()) {
            log.info("Medication photo extraction left fields unmapped: {}", unmapped);
        }

        int prefilledCount = FIELD_LABELS.size() - unmapped.size();
        if (prefilledCount > 0) {
            response.status = MedicationPhotoExtractionResponse.STATUS_PREFILLED;
            response.message = String.format(
                    "%d of %d fields were read from the photo. Review and edit before saving.",
                    prefilledCount, FIELD_LABELS.size());
        } else {
            response.status = MedicationPhotoExtractionResponse.STATUS_MANUAL_ENTRY_REQUIRED;
            response.message = "No medication details could be read from the photo. Please enter them manually.";
        }
        return response;
    }

    private String toMedicationType(String value) {
        if (value.isEmpty()) {
            return "";
        }
        String candidate = value.toUpperCase(Locale.ROOT);
        if (medicationTypeNames().contains(candidate)) {
            return candidate;
        }
        String loggedValue = value.length() > REJECTED_TYPE_LOG_LIMIT ? value.substring(0, REJECTED_TYPE_LOG_LIMIT) + "..." : value;
        log.warn("Medication photo extraction rejected medicationType '{}': not a MedicationType value", loggedValue);
        return "";
    }

    private static List<String> medicationTypeNames() {
        return Arrays.stream(Medication.MedicationType.values()).map(Enum::name).toList();
    }

    private MedicationPhotoExtractionResponse manualEntry(String message) {
        MedicationPhotoExtractionResponse response = new MedicationPhotoExtractionResponse();
        response.status = MedicationPhotoExtractionResponse.STATUS_MANUAL_ENTRY_REQUIRED;
        response.message = message;
        FIELD_LABELS.forEach((key, label) ->
                response.fields.add(new MedicationPhotoExtractedField(key, label, "", false)));
        return response;
    }
}
