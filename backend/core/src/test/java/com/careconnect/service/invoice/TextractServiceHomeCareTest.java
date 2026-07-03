package com.careconnect.service.invoice;

import com.careconnect.dto.chat.AiRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.Block;
import software.amazon.awssdk.services.textract.model.BlockType;
import software.amazon.awssdk.services.textract.model.GetDocumentTextDetectionRequest;
import software.amazon.awssdk.services.textract.model.GetDocumentTextDetectionResponse;
import software.amazon.awssdk.services.textract.model.JobStatus;
import software.amazon.awssdk.services.textract.model.StartDocumentTextDetectionRequest;
import software.amazon.awssdk.services.textract.model.StartDocumentTextDetectionResponse;

import java.io.IOException;
import java.lang.reflect.Field;
import java.util.List;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * OCR pipeline behavior for hiring/home-care documents, which reuse
 * {@link TextractService} through the S3-key-prefix overload.
 */
@ExtendWith(MockitoExtension.class)
class TextractServiceHomeCareTest {

    private static final String HOMECARE_PREFIX = "homecare-documents/";

    @Mock
    private TextractClient textractClient;

    @Mock
    private S3Client s3Client;

    @Mock
    private PdfService pdfService;

    @Mock
    private S3StorageService s3StorageService;

    @InjectMocks
    private TextractService textractService;

    @BeforeEach
    void setUp() throws Exception {
        final Field bucketField = TextractService.class.getDeclaredField("s3BucketName");
        bucketField.setAccessible(true);
        bucketField.set(textractService, "test-bucket");
    }

    private MultipartFile nonEmptyFile(String name) {
        final MultipartFile f = mock(MultipartFile.class);
        when(f.isEmpty()).thenReturn(false);
        when(f.getOriginalFilename()).thenReturn(name);
        return f;
    }

    @Test
    @Timeout(value = 15, unit = TimeUnit.SECONDS)
    void analyzeAndGetResult_validHomeCareDocument_returnsOcrTextAndHomecareKey()
            throws IOException, InterruptedException {
        final MultipartFile file = nonEmptyFile("employment_application.pdf");
        when(pdfService.combineToPdf(any())).thenReturn(new byte[]{1, 2, 3});

        when(textractClient.startDocumentTextDetection(any(StartDocumentTextDetectionRequest.class)))
                .thenReturn(StartDocumentTextDetectionResponse.builder().jobId("job-hc-1").build());

        final Block name = Block.builder().blockType(BlockType.LINE).text("Full Name: Jane Doe").build();
        final Block position = Block.builder().blockType(BlockType.LINE).text("Position: Home Health Aide").build();
        final Block page = Block.builder().blockType(BlockType.PAGE).build();
        when(textractClient.getDocumentTextDetection(any(GetDocumentTextDetectionRequest.class)))
                .thenReturn(GetDocumentTextDetectionResponse.builder()
                        .jobStatus(JobStatus.SUCCEEDED)
                        .blocks(List.of(name, position, page))
                        .nextToken(null)
                        .build());

        final AiRequest.AnalysisResult result =
                textractService.analyzeAndGetResult(List.of(file), HOMECARE_PREFIX);

        assertThat(result.rawText).isEqualTo("Full Name: Jane Doe\nPosition: Home Health Aide");
        assertThat(result.s3Key).startsWith(HOMECARE_PREFIX);
    }

    @Test
    @Timeout(value = 15, unit = TimeUnit.SECONDS)
    void analyzeAndGetResult_defaultOverload_keepsInvoicePrefix()
            throws IOException, InterruptedException {
        final MultipartFile file = nonEmptyFile("invoice.pdf");
        when(pdfService.combineToPdf(any())).thenReturn(new byte[]{1, 2, 3});

        when(textractClient.startDocumentTextDetection(any(StartDocumentTextDetectionRequest.class)))
                .thenReturn(StartDocumentTextDetectionResponse.builder().jobId("job-inv").build());
        when(textractClient.getDocumentTextDetection(any(GetDocumentTextDetectionRequest.class)))
                .thenReturn(GetDocumentTextDetectionResponse.builder()
                        .jobStatus(JobStatus.SUCCEEDED)
                        .blocks(List.of(Block.builder().blockType(BlockType.LINE).text("x").build()))
                        .nextToken(null)
                        .build());

        final AiRequest.AnalysisResult result = textractService.analyzeAndGetResult(List.of(file));

        assertThat(result.s3Key).startsWith("invoices/");
    }

    @Test
    @Timeout(value = 15, unit = TimeUnit.SECONDS)
    void analyzeAndGetResult_emptyOcrResponse_throwsDeterministicFailure()
            throws IOException {
        final MultipartFile file = nonEmptyFile("unreadable_scan.pdf");
        when(pdfService.combineToPdf(any())).thenReturn(new byte[]{1, 2, 3});

        when(textractClient.startDocumentTextDetection(any(StartDocumentTextDetectionRequest.class)))
                .thenReturn(StartDocumentTextDetectionResponse.builder().jobId("job-empty").build());
        when(textractClient.getDocumentTextDetection(any(GetDocumentTextDetectionRequest.class)))
                .thenReturn(GetDocumentTextDetectionResponse.builder()
                        .jobStatus(JobStatus.SUCCEEDED)
                        .blocks(List.of())
                        .nextToken(null)
                        .build());

        // Empty OCR output is surfaced as a well-defined exception (the
        // controller converts it into the manual-entry fallback), not a crash.
        assertThatThrownBy(() -> textractService.analyzeAndGetResult(List.of(file), HOMECARE_PREFIX))
                .isInstanceOf(RuntimeException.class)
                .hasMessage("No text blocks returned.");
    }

    @Test
    @Timeout(value = 15, unit = TimeUnit.SECONDS)
    void analyzeAndGetResult_textractJobFails_returnsFailureState() throws IOException {
        final MultipartFile file = nonEmptyFile("w4.pdf");
        when(pdfService.combineToPdf(any())).thenReturn(new byte[]{1, 2, 3});

        when(textractClient.startDocumentTextDetection(any(StartDocumentTextDetectionRequest.class)))
                .thenReturn(StartDocumentTextDetectionResponse.builder().jobId("job-fail").build());
        when(textractClient.getDocumentTextDetection(any(GetDocumentTextDetectionRequest.class)))
                .thenReturn(GetDocumentTextDetectionResponse.builder()
                        .jobStatus(JobStatus.FAILED)
                        .blocks(List.of())
                        .nextToken(null)
                        .build());

        assertThatThrownBy(() -> textractService.analyzeAndGetResult(List.of(file), HOMECARE_PREFIX))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("failed with status: FAILED");
    }

    @Test
    void analyzeAndGetResult_textractClientError_propagatesAsFailure() throws IOException {
        final MultipartFile file = nonEmptyFile("i9.pdf");
        when(pdfService.combineToPdf(any())).thenReturn(new byte[]{1, 2, 3});

        // Simulates a Textract connectivity/timeout error from the SDK.
        when(textractClient.startDocumentTextDetection(any(StartDocumentTextDetectionRequest.class)))
                .thenThrow(SdkClientException.create("Unable to execute HTTP request: timeout"));

        assertThatThrownBy(() -> textractService.analyzeAndGetResult(List.of(file), HOMECARE_PREFIX))
                .isInstanceOf(SdkClientException.class)
                .hasMessageContaining("timeout");
    }
}
