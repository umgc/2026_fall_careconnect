# CareConnect — Invoice OCR and LLM Pipeline Documentation

**Issue:** #57 | **Team:** D | **Sprint:** 1 | **Course:** SWEN 670  
**Author:** Chris Garcia | **Date:** June 25, 2026 

**Ctrl + Shift + V for better viewing**

---

## Table of Contents

- [CareConnect — Invoice OCR and LLM Pipeline Documentation](#careconnect--invoice-ocr-and-llm-pipeline-documentation)
  - [Table of Contents](#table-of-contents)
  - [1. Purpose](#1-purpose)
  - [2. Pipeline Overview](#2-pipeline-overview)
  - [3. Supported Input Types](#3-supported-input-types)
  - [4. Step-by-Step Pipeline Walkthrough](#4-step-by-step-pipeline-walkthrough)
    - [4.1 File Upload and Input Handling (Frontend)](#41-file-upload-and-input-handling-frontend)
    - [4.2 File Review Screen](#42-file-review-screen)
    - [4.3 API Call to Backend](#43-api-call-to-backend)
    - [4.4 OCR Extraction via AWS Textract](#44-ocr-extraction-via-aws-textract)
    - [4.5 LLM Extraction via LlmExtractionService](#45-llm-extraction-via-llmextractionservice)
    - [4.6 Duplicate Detection](#46-duplicate-detection)
    - [4.7 User Review and Persistence](#47-user-review-and-persistence)
  - [5. Duplicate Detection Behavior and User Decision Points](#5-duplicate-detection-behavior-and-user-decision-points)
  - [6. Current Limitations and Known Failure Modes](#6-current-limitations-and-known-failure-modes)
  - [7. REST API Endpoint Reference](#7-rest-api-endpoint-reference)
  - [8. Source File Reference](#8-source-file-reference)

---

## 1. Purpose

This document establishes a reliable implementation baseline for the CareConnect AI-assisted invoice processing pipeline. It describes the current working process for invoice uploads, OCR extraction, LLM data extraction, duplicate detection, and user review — from the moment a file is selected on the frontend through to the invoice being persisted in the database.

This document is intended for developers, QA engineers, and compliance reviewers working on Team D's invoice features.

---

## 2. Pipeline Overview

The invoice pipeline consists of five sequential stages:

```
User selects file(s)
       ↓
Review screen (user confirms files)
       ↓
POST /v1/api/invoices/extract-llm (multipart upload)
       ↓
AWS Textract (OCR) → raw text
       ↓
LLM Extraction → structured InvoiceDto JSON
       ↓
Duplicate Detection
       ↓
User reviews extracted data → saves invoice
```

> ⚠️ **Availability:** The entire pipeline is gated behind `@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true")`. If AWS is not enabled in the environment, **both `InvoiceController` and `TextractService` are not registered as Spring beans and the pipeline is completely unavailable.** This means the invoice OCR pipeline does not function in local development without AWS credentials configured.

---

## 3. Supported Input Types

The following file types are accepted by the pipeline. Support differs slightly between platforms.

| Format | Extension | Mobile (Android/iOS) | Web | Notes |
|---|---|---|---|---|
| PNG image | `.png` | ✅ | ✅ | Sent as-is via multipart |
| JPEG image | `.jpg`, `.jpeg` | ✅ | ✅ | Sent as-is via multipart |
| HEIC/HEIF image | `.heic`, `.heif` | ✅ | ✅ | Automatically converted to PNG before upload |
| PDF document | `.pdf` | ✅ (via file path) | ✅ (via bytes) | Web uses in-memory bytes; mobile uses file path |
| TIFF image | `.tiff` | ✅ | ✅ | Shown in UI as supported format chip |

**Multiple files:** The pipeline accepts multiple files in a single upload. All files are combined into a single PDF by `PdfService.combineToPdf()` before being sent to Textract. This means a caregiver can photograph multiple pages of an invoice and submit them together as one extraction job.

**HEIC handling:** Apple device photos in HEIC format are detected via file extension, MIME type, or byte-level magic bytes signature check (`ftypheic`, `ftypheix`, etc.) and converted to PNG using Flutter's `ui.instantiateImageCodec` before upload.

---

## 4. Step-by-Step Pipeline Walkthrough

### 4.1 File Upload and Input Handling (Frontend)

**Entry points:** The user has three ways to start the pipeline from `UploadInvoicePage`:

| Action | Method | Description |
|---|---|---|
| **Upload File** | `_onUploadFile()` | Opens the device file picker. Accepts PNG, JPG, JPEG, PDF. Supports multiple file selection. |
| **Take Photo** | `_onTakePhoto()` | Opens the device camera. Captures a single image (max 2048×2048px, 92% quality). |
| **Manual Entry** | `_onManualEntry()` | Skips the pipeline entirely. Opens a blank `InvoiceDetailPage` for manual data entry. |

**Offline detection:** `UploadInvoicePage` monitors connectivity via `Connectivity().onConnectivityChanged`. When offline, an `_OfflineBanner` is shown but the upload options remain visible. However, the pipeline itself requires network connectivity to reach AWS Textract — there is no offline OCR fallback.

---

### 4.2 File Review Screen

Before any API call is made, all selected files are passed to `ReviewPhotosScreen` where the user can review, reorder, or remove files. The user taps **Done** to confirm. Only the files returned from `ReviewPhotosScreen` are sent to the API.

---

### 4.3 API Call to Backend

After review, `InvoiceOcrLlmApi.extractWithLlm()` constructs a `multipart/form-data` POST request to:

```
POST /v1/api/invoices/extract-llm
```

Files are attached under the field name `files`. The request handling differs by platform and file type:

| Input Type | Platform | Handling |
|---|---|---|
| Images (PNG/JPG) | All | Read as bytes, sent as `multipart/form-data` with correct MIME type |
| HEIC images | All | Converted to PNG bytes first, then sent as `image/png` |
| PDF files | Mobile | Sent from file path via `MultipartFile.fromPath()` |
| PDF files | Web | Sent from in-memory bytes via `MultipartFile.fromBytes()` with generated filename `upload_N.pdf` |

A blocking progress dialog (`runWithBlockingDialog`) is shown during the request with the message *"Extracting invoice data. This may take a minute."* The request timeout is **180 seconds** to allow for Textract processing time.

---

### 4.4 OCR Extraction via AWS Textract

`InvoiceController.extractWithLlm()` receives the uploaded files and calls `TextractService.analyzeAndGetResult()`, which performs the following steps:

1. **Combine files into a single PDF** — `PdfService.combineToPdf()` merges all uploaded files (images and PDFs) into a single PDF document.
2. **Generate a unique S3 key** — Format: `invoices/{UUID}-{originalFilename}.pdf`
3. **Upload to S3** — `S3StorageService.upload()` uploads the combined PDF to the configured S3 bucket.
4. **Start async Textract job** — `textractClient.startDocumentTextDetection()` is called with the S3 object location. This returns a `jobId`.
5. **Poll for completion** — The service polls `getDocumentTextDetection()` every **2 seconds** with a maximum timeout of **5 minutes**. Job statuses polled:
   - `IN_PROGRESS` → keep polling
   - `SUCCEEDED` → proceed
   - Any other status → throw `RuntimeException`
6. **Paginate results** — If Textract returns a `nextToken`, additional pages of blocks are fetched until all blocks are collected.
7. **Extract LINE blocks** — Only `BlockType.LINE` blocks are kept. All lines are joined with `\n` to produce the `rawText` string.
8. **Return result** — An `AiRequest.AnalysisResult` object is returned containing `rawText` and the `s3Key` where the original file is stored.

---

### 4.5 LLM Extraction via LlmExtractionService

The `rawText` from Textract is passed to `LlmExtractionService.extractInvoiceData()`, which sends it to the configured AI provider (AWS Bedrock with Nova Lite, as seen in startup logs) with a prompt to extract structured invoice data.

The LLM returns a JSON string. `JsonSanitizer.extractFirstJsonObject()` is then used to strip any surrounding prose or markdown fences from the response by finding the first `{` and matching closing `}` using a depth counter. The sanitized JSON is then deserialized into an `InvoiceDto` using Jackson's `ObjectMapper`.

The following fields are set on the `InvoiceDto` after LLM extraction:
- `aiSummary` — the raw LLM response string (stored for audit/review)
- `documentLink` — the S3 key where the original uploaded file is stored

---

### 4.6 Duplicate Detection

After LLM extraction, the controller checks for duplicate invoices by calling:

```java
service.findDuplicateByProviderAndTotal(providerName, total, invoiceNumber)
```

A duplicate is detected when an existing invoice matches on **all three** of:
- Provider name
- Total amount
- Invoice number

The result is wrapped in an `InvoiceResponseDto` with the following fields:

| Field | Type | Description |
|---|---|---|
| `invoice` | InvoiceDto | The extracted invoice data from the LLM |
| `duplicate` | Boolean | `true` if a matching invoice was found |
| `duplicateId` | String | ID of the existing matching invoice |
| `duplicateInvoiceNumber` | String | Invoice number of the existing match |
| `message` | String | Human-readable duplicate warning message |

---

### 4.7 User Review and Persistence

The extracted `InvoiceResponseDto` is returned to the frontend. The frontend then:

1. Checks `duplicate` flag — if `true`, shows a confirmation dialog (see Section 5).
2. Navigates to `InvoiceDetailPage` with the extracted invoice pre-populated for user review.
3. The invoice is **not saved automatically** — the user must review the extracted data and explicitly save it from `InvoiceDetailPage`.

This human-in-the-loop review step is intentional and ensures AI extraction errors are caught before data is persisted.

---

## 5. Duplicate Detection Behavior and User Decision Points

When a duplicate is detected, the frontend displays an `AlertDialog` with:
- The duplicate warning message (e.g., *"Duplicate invoice detected for provider X with total Y"*)
- The existing invoice number
- Two actions: **Cancel** and **Proceed**

| User Choice | Outcome |
|---|---|
| **Cancel** | The extraction result is discarded. The user is returned to the upload screen. The duplicate is not created. |
| **Proceed** | The user is taken to `InvoiceDetailPage` with the extracted data pre-filled. They can review and save it as a new invoice despite the duplicate warning. |

> **Note:** Duplicate detection is advisory only. It does not block saving. The final decision always rests with the user.

---

## 6. Current Limitations and Known Failure Modes

| # | Limitation / Failure Mode | Area | Details | Owner | Next Action |
|---|---|---|---|---|---|
| 1 | **Pipeline unavailable without AWS** | Availability | `InvoiceController` and `TextractService` are both annotated with `@ConditionalOnProperty(careconnect.aws.enabled=true)`. Without valid AWS credentials and this property set, the entire pipeline is disabled. No fallback OCR exists for local development. | Team D | Confirm AWS Bedrock and Textract credentials are available for the shared dev environment. Document a mock/stub fallback strategy for local development in Sprint 2. |
| 2 | **Textract 5-minute timeout** | Reliability | If the Textract async job does not complete within 5 minutes, a `RuntimeException` is thrown and the upload fails. Large or complex PDFs may hit this limit. | Team D | Test with representative invoice PDFs to determine average processing time. Consider making the timeout configurable via application properties rather than hardcoded. |
| 3 | **No offline invoice extraction** | Offline | The `_OfflineBanner` is shown when offline but there is no offline OCR capability. Invoices cannot be extracted without network connectivity. Manual entry is the only offline path. | Team D | Confirm with team lead whether offline invoice queuing is in scope. If so, document requirements in the SRS and add to Sprint 2 backlog. |
| 4 | **LLM JSON extraction is fragile** | Reliability | `JsonSanitizer.extractFirstJsonObject()` uses a simple bracket-depth algorithm to find the first JSON object in the LLM response. If the LLM returns malformed JSON or wraps the response in unexpected text, parsing will fail with a `JsonProcessingException`. | Team D | Add error handling that returns a user-friendly message when JSON parsing fails rather than a raw 500 error. Consider adding a retry with a stricter prompt if the first extraction fails. |
| 5 | **HEIC conversion not supported on all platforms** | Compatibility | HEIC-to-PNG conversion uses Flutter's `ui.instantiateImageCodec`, which may not support all HEIC variants on all platforms. Unsupported HEIC files will throw an exception during conversion. | Team D | Add a try/catch around HEIC conversion that falls back to uploading the raw bytes with a warning to the user. Add HEIC test cases to the QA test plan. |
| 6 | **Duplicate detection uses exact string matching** | Data Quality | Provider name matching is exact (case-sensitive string comparison). Minor formatting differences (e.g., "Dr. Smith" vs "Dr Smith") will not be detected as duplicates. | Team D | Investigate case-insensitive or fuzzy matching for provider name comparison in `findDuplicateByProviderAndTotal()`. Document the current matching behavior explicitly in the SRS. |
| 7 | **S3 key not guaranteed to persist with invoice record** | Data Integrity | The `documentLink` (S3 key) is set on the `InvoiceDto` from the extraction result and carried through to the detail page, but there is no guaranteed enforcement that it is persisted with the saved invoice record. If the user edits the invoice before saving, the link could be lost. | Team D | Review `InvoiceService.create()` to confirm `documentLink` is always written to the database. Add a test case that verifies the S3 key is present on the saved invoice record. |
| 8 | **LlmExtractionService is `@Nullable`** | Reliability | In `InvoiceController`, `LlmExtractionService` is injected as `@Nullable`. If the bean is not available (e.g., AI provider misconfigured), the controller will throw a `NullPointerException` at extraction time rather than failing gracefully. | Team D | Add a null check on `llmExtractionService` at the start of `extractWithLlm()` and return a clear `503 Service Unavailable` response if the LLM service is not configured. |
| 9 | **Anonymous access permitted on `/extract-llm`** | ⚠️ Security / Cost | Both the `list` and `extract-llm` endpoints wrap `resolveCurrentUser()` in a try/catch and only enforce auth if a user is resolved. Unauthenticated requests can trigger Textract OCR jobs and upload files to S3 at the project's AWS expense. | Team D — flag to Team Lead immediately | Remove the anonymous bypass. Require authentication on all `/extract-llm` calls. If anonymous access was intentional, document the reason and add rate limiting. |
| 10 | **No file size or file count limit enforced** | Security / Reliability | `extractWithLlm()` accepts `List<MultipartFile> files` with no validation on file count or total size. An oversized submission could exhaust the Textract timeout, spike S3 costs, or cause out-of-memory errors in `PdfService.combineToPdf()`. | Team D | Add a max file count (e.g., 10 files) and max file size (e.g., 20MB per file) validation in `InvoiceController`. Return `400 Bad Request` with a clear message if limits are exceeded. |
| 11 | **`PdfService.combineToPdf()` behavior is undocumented** | Reliability | The pipeline depends on `PdfService` to merge all uploaded files into a single PDF before Textract processing, but this service was not included in the reviewed source files. Failure modes for unsupported formats or files exceeding Textract's 3,000-page limit are unknown. | Team D | Review `PdfService.java` and document its supported input types, error handling behavior, and page limit. Add findings to this document in Sprint 2. |
| 12 | **Payment status values are undocumented in SRS and TDD** | Documentation | `invoice_ocr_llm_api.dart` maps wire status strings to a `PaymentStatus` enum with 7 values: `pending`, `overdue`, `pendingInsurance`, `sent`, `paid`, `partialPayment`, and `rejectedInsurance`. None of these values or their meanings appear in the SRS or TDD. | Team D | Document all `PaymentStatus` enum values, their trigger conditions, and their UI representations in a follow-up data dictionary entry in Sprint 2. |

---

## 7. REST API Endpoint Reference

All invoice endpoints are under base path `/v1/api/invoices`. All require a valid JWT except where noted. The entire controller is gated behind `careconnect.aws.enabled=true`.

| Method | Path | Description | Auth Required | Notes |
|---|---|---|---|---|
| `GET` | `/` | List invoices with filters and pagination | ADMIN or CAREGIVER | Supports search, status, provider, patient, date range, amount range filters |
| `GET` | `/{id}` | Get a single invoice by ID | ADMIN or CAREGIVER | |
| `POST` | `/` | Manually create an invoice | ADMIN or CAREGIVER | Used by Manual Entry path — bypasses OCR pipeline |
| `PUT` | `/{id}` | Update an existing invoice | ADMIN or CAREGIVER | |
| `DELETE` | `/{id}` | Delete an invoice | ADMIN or CAREGIVER | |
| `POST` | `/{id}/payments` | Record a payment against an invoice | ADMIN or CAREGIVER | |
| `DELETE` | `/{id}/payments/{paymentId}` | Remove a payment record | ADMIN or CAREGIVER | |
| `POST` | `/extract-llm` | Run the full OCR + LLM extraction pipeline | Optional* | `multipart/form-data`. Files sent under field name `files`. Returns `InvoiceResponseDto`. *Auth is enforced if a valid user is resolved, but anonymous calls are currently permitted — see Gap #1 in Section 6. |

---

## 8. Source File Reference

The following source files were reviewed to produce this document.

| File | Purpose |
|---|---|
| `backend/core/src/main/java/com/careconnect/controller/InvoiceController.java` | REST API endpoints, pipeline orchestration, duplicate detection |
| `backend/core/src/main/java/com/careconnect/service/invoice/TextractService.java` | AWS Textract OCR integration, S3 upload, async polling |
| `frontend/lib/features/invoices/screens/upload_invoice.dart` | Frontend upload entry point, connectivity detection, file picker, camera, review flow |
| `frontend/lib/features/invoices/services/invoice_ocr_llm_api.dart` | HTTP multipart request construction, HEIC conversion, response parsing |

---

*CareConnect | Team D | SWEN 670 | June 25, 2026*