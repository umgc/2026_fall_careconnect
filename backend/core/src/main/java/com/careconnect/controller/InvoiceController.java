package com.careconnect.controller;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.chat.AiRequest;
import com.careconnect.dto.invoice.InvoiceDto;
import com.careconnect.dto.invoice.InvoiceResponseDto;
import com.careconnect.dto.invoice.PaymentDto;
import com.careconnect.model.User;
import com.careconnect.model.invoice.Invoice;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.invoice.LlmExtractionService;
import com.careconnect.service.invoice.InvoiceService;
import com.careconnect.service.invoice.TextractService;
import com.careconnect.util.JsonSanitizer;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.*;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.*;

@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = false)
@RestController
@RequestMapping("/v1/api/invoices")
@Slf4j
public class InvoiceController {

    private final InvoiceService service;
    private final TextractService textractService;
    @org.springframework.lang.Nullable
    private final LlmExtractionService llmExtractionService;
    private final ObjectMapper objectMapper;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final AIServiceFactory aiServiceFactory;
    public InvoiceController(
            InvoiceService service,
            TextractService textractService,
            LlmExtractionService llmExtractionService,            
            ObjectMapper objectMapper,
            SecurityUtil securityUtil,
            AuthorizationService authorizationService,
            AIServiceFactory aiServiceFactory
    ) {

        this.service = service;
        this.textractService = textractService;
        this.llmExtractionService = llmExtractionService;
        this.objectMapper = objectMapper;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
        this.aiServiceFactory = aiServiceFactory;
    }

    // ==============================
    // Invoice CRUD
    // ==============================

    @GetMapping
    public ResponseEntity<Map<String, Object>> list(
            @RequestParam(required = false) String search,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String providerName,
            @RequestParam(required = false) String patientName,
            @RequestParam(required = false) String dueStart,
            @RequestParam(required = false) String dueEnd,
            @RequestParam(required = false) String amountMin,
            @RequestParam(required = false) String amountMax,
            @RequestParam(required = false) String sort,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "25") int pageSize
    ) throws UnauthorizedException {
        // Bug fix (Issue #57 Gap #9): removed anonymous bypass - authentication required.
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        
        Sort s = InvoiceService.resolveSort(sort);
        Pageable pageable = PageRequest.of(page, pageSize, s);

        var statuses = InvoiceService.parseStatuses(status);
        var ds = parseDate(dueStart);
        var de = parseDate(dueEnd);
        var amin = parseDecimal(amountMin);
        var amax = parseDecimal(amountMax);

        Page<InvoiceDto> result = service.list(
                search, statuses, providerName, patientName, ds, de, amin, amax, pageable
        );

        Map<String, Object> body = new HashMap<>();
        body.put("items", result.getContent());
        body.put("page", result.getNumber());
        body.put("pageSize", result.getSize());
        body.put("totalPages", result.getTotalPages());
        body.put("totalItems", result.getTotalElements());

        return ResponseEntity.ok(body);
    }

    @GetMapping("/{id}")
    public ResponseEntity<InvoiceDto> get(@PathVariable String id) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return service.get(id).map(ResponseEntity::ok).orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<InvoiceDto> create(@RequestBody InvoiceDto dto) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        InvoiceDto created = service.create(dto);
        return ResponseEntity.status(201).body(created);
    }

    @PutMapping("/{id}")
    public ResponseEntity<InvoiceDto> update(@PathVariable String id, @RequestBody InvoiceDto dto) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        InvoiceDto updated = service.update(id, dto);
        return ResponseEntity.ok(updated);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable String id) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        service.delete(id);
        return ResponseEntity.noContent().build();
    }

    // ==============================
    // Payments
    // ==============================

    @PostMapping("/{id}/payments")
    public ResponseEntity<InvoiceDto> addPayment(
            @PathVariable String id,
            @RequestBody PaymentDto dto,
            java.security.Principal principal
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        String actor = principal != null ? principal.getName() : "system";
        InvoiceDto updated = service.recordPayment(id, dto, actor);
        return ResponseEntity.ok(updated);
    }

    @DeleteMapping("/{id}/payments/{paymentId}")
    public ResponseEntity<InvoiceDto> removePayment(
            @PathVariable String id,
            @PathVariable String paymentId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        InvoiceDto updated = service.deletePayment(id, paymentId);
        return ResponseEntity.ok(updated);
    }

    // ==============================
    // LLM + Textract Extraction
    // ==============================

    @PostMapping(value = "/extract-llm", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> extractWithLlm(@RequestParam("files") List<MultipartFile> files) throws UnauthorizedException {
        
        // Bug fix (Issue #57 Gap #9): removed anonymous bypass - authentication is required.
        // Previous code wrapped resolveCurrentUser() in try/catch allowing unauthenticated
        // requests to trigger AWS Textract jobs and upload files to S3 at project expense.
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        
        if (isFileListInvalid(files)) {
            return ResponseEntity.badRequest().body("Please provide at least one valid file.");
        }

        try {
            log.info("Received file for OCR: {}", files.get(0).getOriginalFilename());

            // Bug fix (Issue #57 Gap #8): null guard on llmExtractionService.
            // Previously @Nullable injection with no check caused NPE when AI provider
            // was misconfigured. Now returns 503 with a clear message instead.
            if (llmExtractionService == null) {
                log.error("[Invoice] LLM extraction service is not available. Ensure careconnect.aws.enabled=true and AI provider is configured.");
                return ResponseEntity.status(503).body("Invoice extraction service is unavailable. The AI provider is not configured. Contact your system administrator.");
            }

            // Step 1: Textract
            AiRequest.AnalysisResult result = textractService.analyzeAndGetResult(files);

            // Step 2: LLM
            String aiResult = llmExtractionService.extractInvoiceData(result.rawText);

            String sanitizedJson = JsonSanitizer.extractFirstJsonObject(aiResult);

            InvoiceDto invoiceDto =
                    objectMapper.readValue(sanitizedJson, InvoiceDto.class);

            invoiceDto.aiSummary = aiResult;
            invoiceDto.documentLink = result.s3Key;

            // Step 3: Duplicate check
            final String providerName =
                    invoiceDto.provider == null ? null : invoiceDto.provider.name;

            final Double total =
                    invoiceDto.amounts == null ? null : invoiceDto.amounts.total;

            final String invoiceNumber = invoiceDto.invoiceNumber;

            Optional<Invoice> dup =
                    service.findDuplicateByProviderAndTotal(providerName, total, invoiceNumber);

            InvoiceResponseDto payload = new InvoiceResponseDto();
            payload.invoice = invoiceDto;

            if (dup.isPresent()) {
                Invoice existing = dup.get();
                payload.duplicate = true;
                payload.duplicateId = existing.getId();
                payload.duplicateInvoiceNumber = existing.getInvoiceNumber();
                payload.message = String.format(
                        "Duplicate invoice detected for provider %s with total %.2f",
                        providerName,
                        total
                );
            } else {
                payload.duplicate = false;
            }

            return ResponseEntity.ok(payload);

        } catch (Exception e) {
            log.error("Error during LLM extraction", e);
            return ResponseEntity.internalServerError()
                    .body("Failed to process with LLM: " + e.getMessage());
        }
    }

    // ==============================
    // Helpers
    // ==============================

    private boolean isFileListInvalid(List<MultipartFile> files) {
        return files == null
                || files.isEmpty()
                || files.stream().allMatch(MultipartFile::isEmpty);
    }

    private static OffsetDateTime parseDate(String s) {
        return s == null || s.isBlank() ? null : OffsetDateTime.parse(s);
    }

    private static BigDecimal parseDecimal(String s) {
        return s == null || s.isBlank() ? null : new BigDecimal(s);
    }
}