"""Shared codebase revision notes for Team E research document generators."""

from pathlib import Path

REVISION_LABEL = "Codebase refresh: June 2026 (post PR #88 Bedrock/Claude, PR #89 participant handling)"

REVISION_BULLETS = [
    "AI chat opt-in: careconnect.ai.enabled=false by default in application-dev.properties; "
    "AIChatController and Bedrock beans load only when CARECONNECT_AI_ENABLED=true.",
    "Primary AI provider is Bedrock (careconnect.ai.provider=bedrock) via AIServiceFactory → "
    "BedrockAIChatAdapter → BedrockAIChatService; DeepSeek chat path disabled (DefaultAIChatService throws).",
    "BedrockModelSupport adds approved Claude Sonnet 4/4.5/4.6 and Nova models with inference-profile routing.",
    "BedrockAIChatService sends user message only — MedicalContextService / PatientContextRetrievalService "
    "are not wired into the active Bedrock chat path (medical context injection gap).",
    "Voice form AI (symptom/allergy): careconnect.deepseek.enabled=false in dev disables AiSymptomController "
    "and AiAllergyController even though matchIfMissing=true.",
    "Video calls: frontend VideoCallService tracks participantUserIds and POSTs them on /end; "
    "CallController.mergeParticipantUserIds improves multi-party end detection; participant-left vs call-ended WS events.",
    "ChimeService caches attendee credentials per (callId, userId) for idempotent re-join (no duplicate externalUserId errors).",
    "Hybrid retrieval (retrieval_index_chunk, FTS, pgvector Ask AI gateway) still not implemented — gaps below remain open.",
]


def save_document(doc, path: Path) -> Path:
    """Save docx; if target is locked (open in Word), write *_refresh.docx instead."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        doc.save(path)
        print(f"Created: {path}")
        return path
    except PermissionError:
        alt = path.with_name(f"{path.stem}_refresh{path.suffix}")
        doc.save(alt)
        print(f"Created (original locked): {alt}")
        return alt
