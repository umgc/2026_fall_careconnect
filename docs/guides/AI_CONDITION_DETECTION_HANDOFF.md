# AI Condition Detection - Handoff Guide

**Prepared by:** [Srijan Aryal](https://github.com/srijaann)
**Date:** July 2026
**Status:** Research and architecture complete. Code implementation not started.

This guide hands off the voice-based AI condition detection feature to the next cohort. The feature was fully researched and architected during Summer 2026 but was not implemented in code due to a prerequisite dependency on per-attendee audio extraction, which was delivered late in the sprint cycle.

---

## 1) What This Feature Does

CareConnect must analyze patient call audio after each video call and flag potential mental health conditions (depression, anxiety, PTSD, bipolar indicators) as screening signals for caregivers. No single AI model can detect all conditions, so the architecture supports multiple providers through a plug-in registry.

The professor directed that multiple AI providers must be supported because no single model covers all conditions.

---

## 2) MVP Model Selected: KintsugiHealth/dam

| Field | Detail |
|-------|--------|
| Model | KintsugiHealth/dam (Depression-Anxiety Model) |
| Source | https://huggingface.co/KintsugiHealth/dam |
| Conditions | Depression + Anxiety (PHQ-9 / GAD-7 aligned) |
| License | Apache 2.0 (commercial use allowed) |
| Input | Mono WAV, 16 kHz, minimum 30 seconds of speech after voice activity detection |
| Training Data | Approximately 863 hours of phone, tablet, and web speech from approximately 35,000 individuals |
| Output | Depression score + Anxiety score (maps to condition_name + confidence) |
| Validation | Peer-reviewed in Annals of Family Medicine, January 2025 (71% sensitivity, 74% specificity) |
| Feasibility | 8/10, highest among all evaluated candidates |

Why this model: it is the only shortlisted model with documented phone and web conversational training at scale. It detects two conditions in a single inference call. It is acoustic-only (no dependency on transcript quality). Apache 2.0 with full documentation.

---

## 3) Other Providers Evaluated

| Provider | Type | Conditions | Notes |
|----------|------|-----------|-------|
| Kintsugi Voice API | Commercial REST API | Depression, Anxiety | Requires enterprise agreement; strongest clinical validation |
| Sonde Health | Commercial REST API | Depression, Anxiety, Cognitive decline | Patented vocal biomarker platform |
| Ellipsis Health | Commercial REST API | Depression, Anxiety | Transformer-based; adults 18+ |
| AWS Bedrock Claude (text) | Already integrated in repo | PTSD, Bipolar indicators from transcript | Phase 2: extend existing integration |
| AWS Transcribe Call Analytics | Already used for transcription | Sentiment per turn only (not clinical) | Not suitable for condition detection |

---

## 4) Architecture: Plug-in Registry Pattern

```
ConditionDetectionService (orchestrator)
    |
    +-- DamModelAdapter (audio -> depression/anxiety flags)
    +-- BedrockTextAdapter (transcript -> PTSD/bipolar flags)  [Phase 2]
    +-- [Future adapters] (Kintsugi API, Sonde, custom models)
    |
    v
condition_flags table (call_id, model_id, condition_name, confidence, disclaimer)
```

New providers are added by implementing a standard ConditionModelAdapter interface and registering in the model registry. No changes to the core pipeline code are required when adding a new provider.

---

## 5) Prerequisites (What Must Exist Before Implementation)

The DAM model requires per-attendee mono audio files (WAV, 16 kHz) to be available in S3 after a call ends. The two prerequisites are:

1. **Per-attendee audio extraction** - Each call participant's audio must be separated and stored individually in S3. The backend already has KVS (Kinesis Video Streams) recording infrastructure from the video call feature. The per-attendee stream separation logic was implemented during Summer 2026.

2. **Audio format conversion** - KVS stores audio in raw format. The DAM model requires mono WAV at 16 kHz. An ffmpeg conversion step (or equivalent) must produce the correct format before inference.

To verify these prerequisites are working: after a call ends, check the S3 recordings bucket for individual per-attendee audio files. If they exist, the condition detection feature can proceed.

---

## 6) Recommended Implementation Steps

### Step 1: Verify Audio Files in S3

After a video call ends, confirm that per-attendee audio files appear in S3. Check the recordings bucket structure. If files are present, proceed to Step 2. If not, investigate the KVS export pipeline in CallRecordingService.

### Step 2: Create the Python Sidecar for DAM Inference

The KintsugiHealth/dam model runs in Python (PyTorch). Deploy it as a sidecar container alongside the Spring Boot backend in ECS Fargate.

Sidecar responsibilities:
- Accept HTTP POST with audio file path (S3 URI)
- Download audio from S3
- Run voice activity detection (filter silence)
- Run DAM inference
- Return JSON: `{ "depression_score": float, "anxiety_score": float }`

Dockerfile example starting point:
```
FROM python:3.11-slim
RUN pip install torch torchaudio transformers boto3 flask
COPY inference_server.py /app/
CMD ["python", "/app/inference_server.py"]
```

GPU is recommended for production but CPU fallback works for development (inference will be slower).

### Step 3: Create ConditionDetectionService in Spring Boot

Location: `backend/core/src/main/java/com/careconnect/service/`

```java
public interface ConditionModelAdapter {
    List<ConditionFlag> analyze(String audioS3Uri, Long callId, Long patientId);
    String getModelId();
    Set<String> getSupportedConditions();
}
```

The orchestrator calls all registered adapters and persists results.

### Step 4: Create Database Table

Flyway migration (use the next available version number):

```sql
CREATE TABLE condition_flags (
    id BIGSERIAL PRIMARY KEY,
    call_id BIGINT NOT NULL REFERENCES calls(id),
    patient_id BIGINT NOT NULL,
    model_id VARCHAR(100) NOT NULL,
    condition_name VARCHAR(100) NOT NULL,
    confidence DOUBLE PRECISION NOT NULL,
    disclaimer TEXT NOT NULL DEFAULT 'This is a screening flag, not a clinical diagnosis.',
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_condition_flags_call ON condition_flags(call_id);
CREATE INDEX idx_condition_flags_patient ON condition_flags(patient_id);
```

### Step 5: Wire Into Post-Call Pipeline

After a call ends and per-attendee audio is available, trigger condition detection. The natural hook point is after transcription completes (the audio file already exists at that point). Add a call to ConditionDetectionService in the post-call processing flow.

### Step 6: Add Mandatory Disclaimer to UI

All surfaces displaying condition flags must show: "This is a screening flag generated by an AI model. It is not a clinical diagnosis. Consult a healthcare professional for clinical evaluation."

### Step 7 (Phase 2): Bedrock Text Analysis

Extend the existing Bedrock integration to analyze call transcripts for PTSD and bipolar indicators. This reuses the existing BedrockAIChatAdapter infrastructure and adds a new prompt template for condition screening.

---

## 7) Phased Rollout Plan

| Phase | What | Conditions Added | Prerequisite |
|-------|------|-----------------|--------------|
| 1 (MVP) | KintsugiHealth/dam self-hosted (Python sidecar) | Depression, Anxiety | Per-attendee audio in S3 |
| 2 | Bedrock Claude text analysis from transcript | PTSD, Bipolar indicators | Existing integration, minimal new work |
| 3 | Commercial API (Kintsugi Voice or Sonde) | Production-grade depression/anxiety + cognitive | Enterprise agreement required |
| 4 | WavLM + fine-tuned custom heads | Custom conditions | Labeled CareConnect audio dataset |

---

## 8) Key Constraints

- All outputs are screening flags, not diagnoses. Mandatory disclaimer required on every UI surface.
- HIPAA compliance gate must be signed off before production merge.
- DAM model requires minimum 30 seconds of speech after voice activity detection. Short calls may produce no result.
- Commercial APIs (Kintsugi Voice, Sonde Health) require enterprise sales conversations. No public pricing available.
- GPU recommended for DAM inference in production. CPU works for development but is slow (approximately 10x slower).
- Production Bedrock access decisions (D-001, D-002) are still pending from Summer 2026. Fall 2026 cohort should confirm status before Phase 2 work.

---

## 9) Related Files in Repository

| Path | What |
|------|------|
| `backend/core/src/main/java/com/careconnect/service/ChimeService.java` | Existing call infrastructure |
| `backend/core/src/main/java/com/careconnect/service/CallRecordingService.java` | Recording and S3 storage |
| `backend/core/src/main/java/com/careconnect/service/BedrockSentimentService.java` | Existing Bedrock integration (extend for Phase 2) |
| `cloudformation-fargate/templates/04-service.yaml` | ECS task definition (add sidecar container here) |
| `docs/guides/TEAM_A_VIDEO_CALL_QUICKSTART.md` | Video call system documentation |

---

## 10) Questions for the Cohort to Resolve

1. Is GPU instance available in the AWS account for ECS Fargate inference, or should the sidecar run on EC2 with GPU?
2. Has the professor confirmed HIPAA sign-off requirements for voice biomarker data?
3. Should condition flags be visible to patients or caregivers only?
4. What is the minimum call duration threshold below which detection should be skipped entirely?
5. Should detection run synchronously (blocking post-call summary) or asynchronously (results appear later)?

---
