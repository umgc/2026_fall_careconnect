# Ask AI: `/v1/api/ai-chat/chat` vs `/api/ai/ask`

_Finding documented 2026-09-10. Traces the two AI backend endpoints and the frontend methods that call each._

## In plain terms

The app has **two different "chat with the AI" backends** that grew up at different times:

- **`POST /v1/api/ai-chat/chat`** is the **old, general chatbot.** You send it a message plus a
  pile of flags ("include vitals, include meds, include notes…") and it stuffs whatever it can into
  a prompt and returns whatever the AI model says back — as free-form text. It trusts the caller: the
  request body itself says who the user and patient are. Think of it as a general assistant that has
  been handed some context.

- **`POST /api/ai/ask`** is the **new, records-grounded "Ask AI" gateway.** You send it a question
  and a patient ID. It figures out *who you are from your login token* (not from the request body),
  checks whether you're actually allowed to see that patient's records, pulls only the records you're
  permitted to see, and asks the AI a question grounded in those records — returning a **structured**
  answer with citations and an audit trail. If anything is off (no permission, a safety block, an
  error), it returns a controlled "withheld" response instead of leaking text. Think of it as a
  locked-down librarian that only answers from records you're cleared for.

The newer `/api/ai/ask` is the direction the product is moving; `/ai-chat/chat` is legacy.

## Side-by-side

| | `POST /v1/api/ai-chat/chat` (legacy) | `POST /api/ai/ask` (grounded) |
|---|---|---|
| Controller | `AIChatController.sendMessage` | `AiAskController.ask` |
| Path mapping | `/v1/api/ai-chat/chat` | `/api/ai/ask` **and** `/v1/api/ai/ask` |
| Feature flag | `careconnect.ai.enabled` (default **false** — off in dev) | `careconnect.ai.ask.enabled` (default **true**) |
| Who is the caller? | Taken from request body (`userId`, `patientId`) | Resolved from **JWT** only; body's identity is ignored |
| Authorization | None enforced in controller (commented-out `@PreAuthorize`) | `@RequirePermission(USE_AI_FEATURES)` + per-patient/source RBAC via `RetrievalScopeService` |
| What it sends the model | Message + toggles (vitals/meds/notes/mood-pain/allergies), temperature, maxTokens, uploaded files | Query grounded in hybrid-retrieved records the caller is allowed to see |
| Response shape | Free-form `aiResponse` text + `conversationId`, `modelUsed`, timing | Structured `AiAskResponse`: `deliveryStatus` (e.g. `WITHHELD`), citations, `auditId`, `requestId`, `sessionId` |
| Failure behavior | 400/500 with generic error message | Always an `AiAskResponse` with `deliveryStatus=WITHHELD` (one shared error contract, no PHI leakage) |
| File uploads | Supported | Not part of this path |
| Persistence | Creates/continues a `ChatConversation` (history, deactivate, retention policy) | Audit-focused; sibling endpoints for confirmation/share |
| Siblings | `/conversations`, `/history`, `/config`, `/retention-policy` | `/api/ai/ask/confirmation`, `/api/ai/ask/share`, `/api/ai/ask/shares` |

## Frontend methods

Both live in `frontend/lib/services/ai_chat_service.dart` (class `AIChatService`):

| Endpoint | Frontend method | Location |
|---|---|---|
| `POST /api/ai/ask` | `AIChatService.askRecords({query, patientId, sessionId, conversationId, inputModality, locale, sourceTypes, …})` | `ai_chat_service.dart:693` (URL built at `:721`) |
| `POST /v1/api/ai-chat/chat` | `AIChatService.sendMessage({message, userId, patientId, conversationId, include… flags, uploadedFiles, …})` | `ai_chat_service.dart:1086` (URL built at `:1129`) |

Also on the grounded side: `askRecords`'s siblings post to `/api/ai/ask/confirmation` (`:898`),
`/api/ai/ask/share` (`:941`), and GET `/api/ai/ask/shares` (`:1008`).

### Who decides which one runs

The single chat widget `frontend/lib/widgets/ai_chat_improved.dart` picks the endpoint based on its
`mode` (`ai_chat_improved.dart:1187`–`1219`):

```dart
final useGroundedAsk = _isGrounded;               // widget.mode == AiChatMode.groundedRecords
... useGroundedAsk
    ? await AIChatService.askRecords(...)          // -> POST /api/ai/ask
    : await AIChatService.sendMessage(...);        // -> POST /v1/api/ai-chat/chat
```

- **`AiChatMode.groundedRecords` → `askRecords` → `/api/ai/ask`.** Used from the patient dashboard,
  caregiver dashboard, analytics page, medication tracker, and symptom tracker.
- **`AiChatMode.legacyGeneral` → `sendMessage` → `/v1/api/ai-chat/chat`.** Used from the older
  presentation-layer patient dashboard (`features/dashboard/presentation/pages/patient_dashboard.dart`)
  and the in-app chat page (`features/social/in-app-chat/pages/chat-page.dart`).

`AIChatService.sendMessage` is also called directly by `ai_service.dart:98`.

## Takeaway

`/api/ai/ask` is the secure, RBAC-scoped, citation-backed replacement for the legacy
`/v1/api/ai-chat/chat` chatbot. New surfaces (dashboards, trackers, analytics) already route to the
grounded path via `askRecords`; the legacy `sendMessage`/`ai-chat/chat` path remains only for the
older general-chat screens and is gated off by default (`careconnect.ai.enabled=false`).
