package com.careconnect.service.invoice;

import com.careconnect.dto.chat.AiRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.Block;
import software.amazon.awssdk.services.textract.model.BlockType;
import software.amazon.awssdk.services.textract.model.DocumentLocation;
import software.amazon.awssdk.services.textract.model.GetDocumentTextDetectionRequest;
import software.amazon.awssdk.services.textract.model.GetDocumentTextDetectionResponse;
import software.amazon.awssdk.services.textract.model.JobStatus;
import software.amazon.awssdk.services.textract.model.S3Object;
import software.amazon.awssdk.services.textract.model.StartDocumentTextDetectionRequest;
import software.amazon.awssdk.services.textract.model.StartDocumentTextDetectionResponse;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor

@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = false)
public class TextractService {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(TextractService.class);

    private final TextractClient textractClient;
    private final S3Client s3Client;
    private final PdfService pdfService;
    private final S3StorageService s3StorageService;
    private static final long POLL_INTERVAL_MS = 2000;       // 2 seconds
    private static final long TIMEOUT_MS = 5 * 60 * 1000;    // 5 minutes

    @Value("${aws.s3.bucket-name}")
    private String s3BucketName;

    /**
     * Returns raw text lines extracted by Textract.
     */
    public String getBlocksFromFiles(List<MultipartFile> files) throws IOException, InterruptedException {
        return analyzeAndGetResult(files).rawText;
    }

    /**
     * Combines, uploads, runs Textract text detection, and returns raw text and S3 key.
     */
    public AiRequest.AnalysisResult analyzeAndGetResult(List<MultipartFile> files) throws IOException, InterruptedException {
        return analyzeAndGetResult(files, "invoices/");
    }

    /**
     * Same pipeline with a caller-supplied S3 key prefix, so non-invoice
     * documents (e.g. home-care onboarding forms) land in their own folder.
     */
    public AiRequest.AnalysisResult analyzeAndGetResult(List<MultipartFile> files, String s3KeyPrefix) throws IOException, InterruptedException {
        if (s3KeyPrefix == null || s3KeyPrefix.isBlank()) {
            throw new IllegalArgumentException("S3 key prefix cannot be null or blank.");
        }
        String normalizedPrefix = s3KeyPrefix.endsWith("/") ? s3KeyPrefix : s3KeyPrefix + "/";

        if (files == null || files.isEmpty() || files.stream().allMatch(MultipartFile::isEmpty)) {
            throw new IllegalArgumentException("File list cannot be null or empty.");
        }

        byte[] combinedPdfData = pdfService.combineToPdf(files);
        String fileName = files.get(0).getOriginalFilename();
        // Ensure fileName is not null or empty
        if (fileName == null || fileName.trim().isEmpty()) {
            throw new IllegalArgumentException("Invalid file name");
        }

        // Remove extra extension if necessary
        String baseName = fileName;
        if (fileName.toLowerCase().endsWith(".pdf")) {
            baseName = fileName.substring(0, fileName.length() - 4);
        }

        String s3Key = normalizedPrefix + UUID.randomUUID() + "-" + fileName + ".pdf";

        s3StorageService.upload(combinedPdfData, s3Key, "application/pdf");

        List<Block> blocks = detectTextFromS3(s3Key);

        if (blocks.isEmpty()) {
            throw new RuntimeException("No text blocks returned.");
        }

        String rawText = blocks.stream()
                .filter(b -> b.blockType() == BlockType.LINE)
                .map(Block::text)
                .collect(Collectors.joining("\n"));

        return new AiRequest.AnalysisResult(rawText, s3Key);
    }
    /**
     * Runs async Textract Text Detection for a PDF in S3 and returns all blocks.
     */
    private List<Block> detectTextFromS3(String s3Key) throws InterruptedException {
        S3Object s3Object = S3Object.builder()
                .bucket(s3BucketName)
                .name(s3Key)
                .build();

        DocumentLocation docLocation = DocumentLocation.builder()
                .s3Object(s3Object)
                .build();

        StartDocumentTextDetectionRequest startReq = StartDocumentTextDetectionRequest.builder()
                .documentLocation(docLocation)
                .build();

        StartDocumentTextDetectionResponse startRes = textractClient.startDocumentTextDetection(startReq);
        String jobId = startRes.jobId();
        log.info("Started Textract text detection job: {}", jobId);

        GetDocumentTextDetectionRequest getReq = GetDocumentTextDetectionRequest.builder()
                .jobId(jobId)
                .build();

        GetDocumentTextDetectionResponse getRes;
        String status;
        long startTime = System.currentTimeMillis();

        do {
            Thread.sleep(POLL_INTERVAL_MS);

            // timeout check
            if (System.currentTimeMillis() - startTime > TIMEOUT_MS) {
                throw new RuntimeException("Textract job " + jobId + " timed out after " + (TIMEOUT_MS / 1000) + " seconds.");
            }
            getRes = textractClient.getDocumentTextDetection(getReq);
            status = getRes.jobStatusAsString();
            log.info("Job status for {}: {}", jobId, status);

        } while (JobStatus.IN_PROGRESS.toString().equals(status));

        if (!JobStatus.SUCCEEDED.toString().equals(status)) {
            throw new RuntimeException("Textract job " + jobId + " failed with status: " + status);
        }
        List<Block> allBlocks = new ArrayList<>(getRes.blocks());
        String nextToken = getRes.nextToken();
        while (nextToken != null) {
            log.info("Fetching next page for job {}", jobId);
            getRes = textractClient.getDocumentTextDetection(
                    GetDocumentTextDetectionRequest.builder()
                            .jobId(jobId)
                            .nextToken(nextToken)
                            .build());
            allBlocks.addAll(getRes.blocks());
            nextToken = getRes.nextToken();
        }

        return allBlocks;
    }
}
