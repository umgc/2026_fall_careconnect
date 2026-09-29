package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.stream.Collectors;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;

import com.careconnect.ai.AIService;
import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.MedicationPhotoExtractedField;
import com.careconnect.dto.MedicationPhotoExtractionResponse;
import com.careconnect.testsupport.fixtures.MedicationPhotoFixtures;
import com.fasterxml.jackson.databind.ObjectMapper;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextRequest;

/**
 * F-01 Medication Photo Capture, service layer (TC-MED-PHOTO-001..019).
 *
 * <p>
 * Validates MedicationPhotoExtractionService: in-memory Textract OCR, LLM
 * structuring, Table 25 fallbacks, and the ADR-05 rule that image bytes are never
 * logged or returned. TextractClient and AIServiceFactory are mocked (no live
 * AWS, per TESTING_NORMS.md); a logback ListAppender captures the service logger.
 * </p>
 */
class MedicationPhotoExtractionServiceTest {

    private TextractClient textract;
    private AIService aiService;
    private AIServiceFactory factory;
    private MedicationPhotoExtractionService service;
    private ListAppender<ILoggingEvent> logs;
    private Logger serviceLogger;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        textract = mock(TextractClient.class);
        aiService = mock(AIService.class);
        factory = mock(AIServiceFactory.class);
        when(factory.getService()).thenReturn(aiService);
        final ObjectProvider<TextractClient> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(textract);
        service = new MedicationPhotoExtractionService(provider, factory, new ObjectMapper());

        serviceLogger = (Logger) LoggerFactory.getLogger(MedicationPhotoExtractionService.class);
        serviceLogger.setLevel(Level.DEBUG);
        logs = new ListAppender<>();
        logs.start();
        serviceLogger.addAppender(logs);
    }

    @AfterEach
    void tearDown() {
        serviceLogger.detachAppender(logs);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private void ocrOk() {
        when(textract.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(MedicationPhotoFixtures.ocrResponse());
    }

    private void llmReturns(String raw) {
        final ChatResponse r = new ChatResponse();
        r.setAiResponse(raw);
        when(aiService.processChat(any(ChatRequest.class))).thenReturn(r);
    }

    private static MedicationPhotoExtractedField field(MedicationPhotoExtractionResponse r, String key) {
        return r.fields.stream().filter(f -> f.key.equals(key)).findFirst().orElseThrow();
    }

    private List<String> logLines() {
        return logs.list.stream().map(ILoggingEvent::getFormattedMessage).collect(Collectors.toList());
    }

    private List<ILoggingEvent> logsAt(Level level) {
        return logs.list.stream().filter(e -> e.getLevel() == level).collect(Collectors.toList());
    }

    private void assertManualEntryAllBlank(MedicationPhotoExtractionResponse r) {
        assertThat(r.status).isEqualTo(MedicationPhotoExtractionResponse.STATUS_MANUAL_ENTRY_REQUIRED);
        assertThat(r.message).isNotBlank();
        assertThat(r.fields).extracting(f -> f.key)
                .containsExactly("medicationName", "dosage", "frequency", "medicationType");
        assertThat(r.fields).allSatisfy(f -> {
            assertThat(f.value).isEmpty();
            assertThat(f.machineGenerated).isFalse();
        });
    }

    // ── Happy path ───────────────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MED-PHOTO-001: label prefills all four fields, each machineGenerated")
    void happyPath_allFieldsPrefilled() {
        // Arrange
        ocrOk();
        llmReturns(MedicationPhotoFixtures.fullLlmJson());
        // Act
        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());
        // Assert
        assertThat(r.status).isEqualTo(MedicationPhotoExtractionResponse.STATUS_PREFILLED);
        assertThat(r.fields).extracting(f -> f.key)
                .containsExactly("medicationName", "dosage", "frequency", "medicationType");
        assertThat(field(r, "medicationName").value).isEqualTo("Lisinopril");
        assertThat(field(r, "dosage").value).isEqualTo("10 mg");
        assertThat(field(r, "frequency").value).isEqualTo("Once daily");
        assertThat(field(r, "medicationType").value).isEqualTo("PRESCRIPTION");
        assertThat(r.fields).allSatisfy(f -> assertThat(f.machineGenerated).isTrue());
        assertThat(field(r, "dosage").label).isEqualTo("Dosage");
    }

    @Test
    @DisplayName("TC-MED-PHOTO-002: exact bytes go to Textract once, only LINE text reaches the LLM prompt")
    void happyPath_textractGetsBytesOnce_llmGetsLineTextOnly() {
        // Arrange
        ocrOk();
        llmReturns(MedicationPhotoFixtures.fullLlmJson());
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();
        // Act
        service.extract(bytes);
        // Assert
        final ArgumentCaptor<DetectDocumentTextRequest> req = ArgumentCaptor.forClass(DetectDocumentTextRequest.class);
        verify(textract, times(1)).detectDocumentText(req.capture());
        assertThat(req.getValue().document().bytes().asByteArray()).isEqualTo(bytes);
        assertThat(req.getValue().document().s3Object()).as("no S3 reference (ADR-05)").isNull();
        verifyNoMoreInteractions(textract);

        final ArgumentCaptor<ChatRequest> chat = ArgumentCaptor.forClass(ChatRequest.class);
        verify(aiService, times(1)).processChat(chat.capture());
        final String prompt = chat.getValue().getMessage();
        assertThat(prompt).contains(MedicationPhotoFixtures.LABEL_LINE_1, MedicationPhotoFixtures.LABEL_LINE_2);
        assertThat(prompt).doesNotContain("IGNORED");
        MedicationPhotoFixtures.imageLeakNeedles().forEach(n -> assertThat(prompt).doesNotContain(n));
    }

    // ── Table 25 row 1: OCR failure ──────────────────────────────────────────

    @Test
    @DisplayName("TC-MED-PHOTO-003: Textract throws -> manual entry, no LLM call, no retry")
    void ocrThrows_manualEntry_noRetry() {
        when(textract.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenThrow(new RuntimeException("Textract timeout"));

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertManualEntryAllBlank(r);
        assertThat(r.message).containsIgnoringCase("could not be read");
        verify(textract, times(1)).detectDocumentText(any(DetectDocumentTextRequest.class));
        verify(factory, never()).getService();
        verify(aiService, never()).processChat(any());
    }

    @Test
    @DisplayName("TC-MED-PHOTO-004: OCR returns no LINE text -> manual entry, LLM not called")
    void ocrEmpty_manualEntry() {
        when(textract.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenReturn(MedicationPhotoFixtures.emptyOcrResponse());

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertManualEntryAllBlank(r);
        assertThat(r.message).containsIgnoringCase("no text");
        verify(aiService, never()).processChat(any());
    }

    @Test
    @DisplayName("TC-MED-PHOTO-005: OCR failure logs one WARN with the cause and no image bytes")
    void ocrThrows_warnWithCause_noBytes() {
        when(textract.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenThrow(new IllegalStateException("Textract timeout"));

        service.extract(MedicationPhotoFixtures.imageBytes());

        final List<ILoggingEvent> warns = logsAt(Level.WARN);
        assertThat(warns).hasSize(1);
        assertThat(warns.get(0).getFormattedMessage())
                .contains("IllegalStateException", "Textract timeout");
        MedicationPhotoFixtures.imageLeakNeedles()
                .forEach(n -> assertThat(String.join("\n", logLines())).doesNotContain(n));
        assertThat(warns.get(0).getThrowableProxy()).as("no stack trace carrying payload").isNull();
    }

    @Test
    @DisplayName("TC-MED-PHOTO-006: AWS disabled (no TextractClient bean) -> manual entry with WARN")
    @SuppressWarnings("unchecked")
    void awsDisabled_manualEntry() {
        final ObjectProvider<TextractClient> absent = mock(ObjectProvider.class);
        when(absent.getIfAvailable()).thenReturn(null);
        final MedicationPhotoExtractionService svc =
                new MedicationPhotoExtractionService(absent, factory, new ObjectMapper());

        final MedicationPhotoExtractionResponse r = svc.extract(MedicationPhotoFixtures.imageBytes());

        assertManualEntryAllBlank(r);
        assertThat(r.message).containsIgnoringCase("not available");
        assertThat(logsAt(Level.WARN)).hasSize(1);
        verify(aiService, never()).processChat(any());
    }

    // ── Table 25 row 2: unmapped fields / LLM failure ────────────────────────

    @Test
    @DisplayName("TC-MED-PHOTO-007: missing dosage stays blank, other fields stay machineGenerated")
    void missingDosage_blank_othersMachineGenerated() {
        ocrOk();
        llmReturns(MedicationPhotoFixtures.llmJson("Lisinopril", "", "Once daily", "PRESCRIPTION"));

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertThat(r.status).isEqualTo(MedicationPhotoExtractionResponse.STATUS_PREFILLED);
        assertThat(field(r, "dosage").value).isEmpty();
        assertThat(field(r, "dosage").machineGenerated).isFalse();
        assertThat(field(r, "medicationName").machineGenerated).isTrue();
        assertThat(field(r, "frequency").machineGenerated).isTrue();
        assertThat(field(r, "medicationType").machineGenerated).isTrue();
    }

    @Test
    @DisplayName("TC-MED-PHOTO-008: absent key and non-scalar value both become blank, not guessed")
    void absentKeyAndNonScalar_blank() {
        ocrOk();
        llmReturns("{\"medicationName\":\"Lisinopril\",\"frequency\":{\"nested\":\"x\"}}");

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertThat(field(r, "medicationName").value).isEqualTo("Lisinopril");
        assertThat(field(r, "dosage").value).isEmpty();
        assertThat(field(r, "frequency").value).isEmpty();
        assertThat(field(r, "medicationType").value).isEmpty();
        assertThat(r.status).isEqualTo(MedicationPhotoExtractionResponse.STATUS_PREFILLED);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-009: unmapped fields logged at INFO by key")
    void unmapped_infoLogListsKeys() {
        ocrOk();
        llmReturns(MedicationPhotoFixtures.llmJson("Lisinopril", "", "", "PRESCRIPTION"));

        service.extract(MedicationPhotoFixtures.imageBytes());

        final List<ILoggingEvent> infos = logsAt(Level.INFO);
        assertThat(infos).hasSize(1);
        assertThat(infos.get(0).getFormattedMessage()).contains("dosage", "frequency")
                .doesNotContain("medicationName");
    }

    @Test
    @DisplayName("TC-MED-PHOTO-010: every field blank from LLM -> MANUAL_ENTRY_REQUIRED")
    void allBlank_manualEntryRequired() {
        ocrOk();
        llmReturns(MedicationPhotoFixtures.llmJson("", "", "", ""));

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertManualEntryAllBlank(r);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-011: LLM call throws -> manual entry, single attempt, no label text in log")
    void llmThrows_manualEntry_noRetry_noLabelTextInLog() {
        ocrOk();
        when(aiService.processChat(any(ChatRequest.class)))
                .thenThrow(new RuntimeException("bedrock down " + MedicationPhotoFixtures.LABEL_LINE_1));

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertManualEntryAllBlank(r);
        verify(aiService, times(1)).processChat(any(ChatRequest.class));
        final String all = String.join("\n", logLines());
        assertThat(all).contains("RuntimeException");
        assertThat(all).doesNotContain(MedicationPhotoFixtures.LABEL_LINE_1);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-012: AIServiceFactory.getService throws -> manual entry")
    void factoryThrows_manualEntry() {
        ocrOk();
        when(factory.getService()).thenThrow(new IllegalStateException("no provider"));

        assertManualEntryAllBlank(service.extract(MedicationPhotoFixtures.imageBytes()));
    }

    @ParameterizedTest(name = "TC-MED-PHOTO-013: LLM output [{0}] -> manual entry")
    @ValueSource(strings = {"Sorry, I cannot help with that.", "{not valid json", "[1,2,3]", ""})
    void llmMalformed_manualEntry(String raw) {
        ocrOk();
        llmReturns(raw);

        assertManualEntryAllBlank(service.extract(MedicationPhotoFixtures.imageBytes()));
        assertThat(logsAt(Level.WARN)).hasSize(1);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-014: markdown-wrapped JSON with prose around it still parses")
    void markdownWrappedJson_parses() {
        ocrOk();
        llmReturns("Here you go:\n```json\n" + MedicationPhotoFixtures.fullLlmJson() + "\n```\n");

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertThat(r.status).isEqualTo(MedicationPhotoExtractionResponse.STATUS_PREFILLED);
        assertThat(field(r, "medicationName").value).isEqualTo("Lisinopril");
    }

    // ── Table 25 row 3: medicationType mapping (KI-05) ───────────────────────

    @ParameterizedTest(name = "TC-MED-PHOTO-015: valid medicationType [{0}] is accepted")
    @ValueSource(strings = {"PRESCRIPTION", "OVER_THE_COUNTER", "SUPPLEMENT", "HERBAL", "EMERGENCY"})
    void validMedicationTypes_accepted(String type) {
        ocrOk();
        llmReturns(MedicationPhotoFixtures.llmJson("X", "1", "daily", type));

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertThat(field(r, "medicationType").value).isEqualTo(type);
        assertThat(field(r, "medicationType").machineGenerated).isTrue();
        assertThat(logsAt(Level.WARN)).isEmpty();
    }

    @Test
    @DisplayName("TC-MED-PHOTO-016: lowercase and padded type is normalised to the enum name")
    void medicationType_caseAndWhitespaceNormalised() {
        ocrOk();
        llmReturns(MedicationPhotoFixtures.llmJson("X", "1", "daily", "  herbal "));

        assertThat(field(service.extract(MedicationPhotoFixtures.imageBytes()), "medicationType").value)
                .isEqualTo("HERBAL");
    }

    @ParameterizedTest(name = "TC-MED-PHOTO-017: invalid medicationType [{0}] -> blank, other fields kept, WARN")
    @ValueSource(strings = {"Over the counter", "VITAMIN", "PRESCRIPTION; DROP TABLE", "OTC"})
    void invalidMedicationType_blankAndWarn(String type) {
        ocrOk();
        llmReturns(MedicationPhotoFixtures.llmJson("Lisinopril", "10 mg", "Once daily", type));

        final MedicationPhotoExtractionResponse r = service.extract(MedicationPhotoFixtures.imageBytes());

        assertThat(field(r, "medicationType").value).isEmpty();
        assertThat(field(r, "medicationType").machineGenerated).isFalse();
        assertThat(field(r, "medicationName").machineGenerated).isTrue();
        assertThat(r.status).isEqualTo(MedicationPhotoExtractionResponse.STATUS_PREFILLED);
        final List<ILoggingEvent> warns = logsAt(Level.WARN);
        assertThat(warns).hasSize(1);
        assertThat(warns.get(0).getFormattedMessage()).contains("rejected medicationType");
    }

    // ── ADR-05 / 11.4: image bytes never logged or returned ──────────────────

    @Test
    @DisplayName("TC-MED-PHOTO-018: no log line on success, OCR fail, LLM fail, or bad type contains image content")
    void noImageContentInAnyLog() {
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();

        // success path with an invalid type (exercises WARN + INFO)
        ocrOk();
        llmReturns(MedicationPhotoFixtures.llmJson("X", "", "", "BOGUS"));
        service.extract(bytes);
        // OCR failure whose message tries to echo the payload
        when(textract.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenThrow(new RuntimeException("failed"));
        service.extract(bytes);
        // LLM failure and malformed output
        ocrOk();
        when(aiService.processChat(any(ChatRequest.class))).thenThrow(new RuntimeException("llm"));
        service.extract(bytes);
        llmReturns("garbage " + MedicationPhotoFixtures.LABEL_LINE_1);
        service.extract(bytes);

        assertThat(logs.list).isNotEmpty();
        final String everything = logs.list.stream()
                .map(e -> e.getFormattedMessage() + " " + e.getThrowableProxy())
                .collect(Collectors.joining("\n"));
        MedicationPhotoFixtures.imageLeakNeedles().forEach(n -> assertThat(everything).doesNotContain(n));
        assertThat(everything).as("OCR text not echoed on parse failure")
                .doesNotContain(MedicationPhotoFixtures.LABEL_LINE_1);
    }

    @Test
    @DisplayName("TC-MED-PHOTO-019: serialized responses (success and every fallback) contain no image content")
    void serializedResponsesHaveNoImageContent() throws Exception {
        final ObjectMapper om = new ObjectMapper();
        final byte[] bytes = MedicationPhotoFixtures.imageBytes();
        ocrOk();
        llmReturns(MedicationPhotoFixtures.fullLlmJson());
        final String ok = om.writeValueAsString(service.extract(bytes));
        when(textract.detectDocumentText(any(DetectDocumentTextRequest.class)))
                .thenThrow(new RuntimeException("boom"));
        final String fail = om.writeValueAsString(service.extract(bytes));

        for (final String json : List.of(ok, fail)) {
            MedicationPhotoFixtures.imageLeakNeedles().forEach(n -> assertThat(json).doesNotContain(n));
            assertThat(json).contains("\"status\"", "\"message\"", "\"fields\"", "\"machineGenerated\"");
        }
    }

    @Test
    @DisplayName("TC-MED-PHOTO-020: invalid-type WARN carries only a short newline-free excerpt of label text")
    void invalidMedicationType_warnExcerptIsShortAndSingleLine() {
        ocrOk();
        final String longMultiline = ("Take with food\nLISINOPRIL 10 MG " + "x".repeat(300));
        llmReturns(MedicationPhotoFixtures.llmJson("Lisinopril", "10 mg", "daily", longMultiline.replace("\n", "\\n")));

        service.extract(MedicationPhotoFixtures.imageBytes());

        final List<ILoggingEvent> warns = logsAt(Level.WARN);
        assertThat(warns).hasSize(1);
        final String msg = warns.get(0).getFormattedMessage();
        assertThat(msg).contains("rejected medicationType");
        assertThat(msg).doesNotContain("\n").doesNotContain("\r");
        assertThat(msg.length()).as("bounded WARN length").isLessThan(200);
    }
}
