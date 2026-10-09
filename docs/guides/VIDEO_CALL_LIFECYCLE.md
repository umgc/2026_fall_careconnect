# Video Call — Feature Lifecycle Reference

A code-path trace of the video call feature from the camera icon to the post-call summary.
Every claim here was verified against the source; line numbers are from the state of the repo
when this was written and may drift — treat the **class and method names** as the stable part.

Companion docs (setup and ops, not code paths):
- `docs/guides/TEAM_A_VIDEO_CALL_QUICKSTART.md` — local env, AWS creds, KVS/ngrok setup
- `docs/guides/CONFERENCE_CALL_GUIDE.md` — add-participant feature notes
- `docs/guides/SENTIMENT_ADAPTIVE_RUNBOOK.md` — sentiment capture-mode tuning

---

## 0. Orientation

```
Flutter (Amplify)  ──REST──▶  Spring Boot (ECS Fargate)  ──▶  RDS PostgreSQL
       │                              │
       │                              ├──▶ Amazon Chime SDK Meetings   (media)
       │                              ├──▶ Chime SDK Media Pipelines   (recording → S3)
       │                              ├──▶ Kinesis Video Streams       (per-attendee audio)
       │                              ├──▶ AWS Transcribe              (post-call, per attendee)
       │                              └──▶ AWS Bedrock                 (sentiment + summary)
       │
       └──WebSocket──▶ CallNotificationHandler   (ringing, sentiment push, recording state)
```

Two transports, and they do different jobs:

| Transport | Carries | Fails how |
| --- | --- | --- |
| REST `/api/v3/calls/**` | session creation, join, sentiment upload, recording, end | HTTP status, surfaced in UI |
| WebSocket | ringing, accept/decline, sentiment results, recording state, call-ended | silent — no ring, no live dashboard |

**The call screen is one widget for everyone**: `HybridVideoCallWidget`. `isInitiator` and the
resolved role (`_isCaregiverView` / `_isPatientView` / `_isCareTeamCall`) drive every branch.

---

## 1. Entry points

### Live — a user can start a call from these six places

| # | Screen | Trigger | Handoff style |
| --- | --- | --- | --- |
| 1 | `frontend/lib/screens/main_screen.dart:824` | global FAB `Icons.video_call` | `Navigator.push` — **typed** |
| 2 | `frontend/lib/features/health/caregiver-patient-list/widgets/patient_header_card.dart:423` | videocam in patient header | URL `/video-call-chime` |
| 3 | `frontend/lib/features/social/presentation/pages/chat_room_screen.dart:1393` | app-bar videocam | URL |
| 4 | `frontend/lib/features/dashboard/patient_dashboard/pages/patient_dashboard.dart:1023` | provider sheet "Video Call" row | `CallIntegrationHelper` |
| 5 | join link / deep link | `/video-call-chime?...` | URL |
| 6 | accept an incoming call | `CallNotificationService._acceptedCallLocation` | URL |

The FAB only renders where `showCallFab: true` — **Home tab only**, for both roles
(`frontend/lib/config/navigation/bottom_nav_config.dart:104` and `:164`).
It is also the **only** way to start a `CARE_TEAM` call.

### Dead — has call UI, unreachable

| File | Why |
| --- | --- |
| `frontend/lib/features/dashboard/presentation/pages/caregiver_dashboard.dart:1281` | only used by `CaregiverPatientsTab`, which nothing instantiates |
| `frontend/lib/features/dashboard/presentation/pages/patient_dashboard.dart:1224` | nothing imports it |
| `frontend/lib/services/video_call_integration.dart` | nothing imports it |

⚠️ There are **two `CaregiverDashboard` classes and three `PatientDashboard` classes**.
The live caregiver Home is `features/dashboard/caregiver-dashboard/pages/caregiver-dashboard.dart`;
the live patient Home is `features/dashboard/patient_dashboard/pages/patient_dashboard.dart`.

### Handoff-style consequence

Entry points 1 and 4 pass typed constructor args — a signature change breaks the build.
Entry points 2, 3, 5, 6 pass query-string params parsed in `app_router.dart:1102-1124` —
a signature change compiles fine and **silently drops the value**.

---

## 2. The 15 steps

### Step 1 — Camera icon
`_buildGlobalCallFab()` → gated on user != null, role in {PATIENT, CAREGIVER}, and the tab's
`showCallFab`. Receiver must already have run `CallNotificationService.initialize()`
(`main_screen.dart:245` / patient dashboard `:75`) or they cannot be rung.

### Step 2 — Pick a callee (caller only; nothing reaches the receiver yet)
`_showQuickCallPicker()` → `FutureBuilder` over `_loadQuickCallTargets(user)`.

- **PATIENT**: 1 call — `getPatientLinkedCaregiverLinks`, filtered on `patientVideoCallsEnabled`
  (anything not literally `"false"` counts as enabled).
- **CAREGIVER**: `1 + N` **sequential** calls — patients, then each patient's other caregivers,
  deduped into `_CareTeamAggregate`. No `patientVideoCallsEnabled` filter on this path.

`_QuickCallTarget.isCareTeamCall` (`main_screen.dart:1254`) is the highest-leverage getter in
the step — it becomes `callKind: 'CARE_TEAM'`, which later disables sentiment entirely.

### Step 3 — Permission check + handoff (caller only)
`ApiService.canInitiateVideoCall` — client-side only, re-runs the same 1+N fetch, and returns
`false` on **every** failure mode (expired token, 500, timeout all render as "not allowed").
Call id is minted client-side: `chime_call_${DateTime.now().millisecondsSinceEpoch}`.

### Step 4 — Call screen init (paths diverge here)
`initState` → `_loadCurrentRole()` + `_initializeCall()` (both resolve role; redundant).

| | Caller `isInitiator: true` | Receiver `false` |
| --- | --- | --- |
| patient-context resolution fails | **fatal** | tolerated (`null`) |
| `POST /sessions` | ✅ | ❌ |
| `POST /{callId}/join` | ✅ `inviteeUserId` = recipient | ✅ `inviteeUserId` = self |
| send invitation | ✅ | ❌ |

`resolveCallSessionPatientUserId` (`video_call_service.dart:28`) anchors every call to exactly
one patient, else throws.

### Step 5 — Backend `/join`
`CallController.joinCall` → `ensureJoinAuthorized` → `recordJoin` → `ChimeService.joinMeeting`.

- **Durable join happens before Chime**; `revertJoinAfterChimeFailure` rolls it back on failure.
- `electRecordingStart(sessionId, JOINED, 2)` — the **recording-owner election**, won by the
  *second* joiner, exactly once across all nodes.
- `createMeeting` is idempotent via `clientRequestToken(deterministicToken(callId))`.
- `toOpaqueChimeExternalUserId` (`ChimeService:1108`) = `UUID.nameUUIDFromBytes(...)` — carries
  **no name, role, or raw user id**. This is why speaker labels must be inferred client-side.
- Auto-record/KVS only when `careconnect.recording.system-transcription-enabled` (**default false**).

### Step 6 — Ringing (WebSocket only)
`sendCallInvitation` → `CallNotificationHandler.handleCallInvitation`.

Server rules: `requireActiveParticipant`, server **overwrites** `recipientId`,
patient→patient rejected, patient→caregiver needs an active link **and**
`isPatientVideoCallsEnabled`. Caregiver→anyone has no extra rule.

Caller waits on an **8-second completer** for `call-invitation-sent` / `call-invitation-failed`.
`true` means "handed to an open socket", not "answered".
On failure → copy-join-link snackbar (`buildCalleeJoinUrl`).

### Step 7 — Accept / decline
- **Accept**: `accept-call` → server notifies *all* other participants with `call-answered`
  (cosmetic snackbar only — the caller was already in the meeting). Receiver navigates to
  `/video-call-chime?...&initiator=false`.
- **Decline**: `decline-call` → `declineInvitation` → `INVITED → DECLINED`. If the session is
  `ACTIVE` with nobody left joined or invited, the decliner becomes `terminationOwner` and the
  **full `CallTerminationExecutor` runs inside the WebSocket handler**.
- Caller gets both a snackbar and a full-screen `_buildCallRejectedSummary()` with retry.

### Step 8 — In the call
Video is an `<iframe srcdoc>` running the Chime JS SDK, not Flutter.
`chime_meeting_embed_web.dart`; Dart ↔ JS over `postMessage`.

- **Dart → JS** (`source: 'careconnect-flutter'`): `toggle-audio`, `toggle-video`,
  `switch-camera`, channel restart. **None hit the backend** — the remote party never learns
  you muted. Return value means "posted", not "succeeded".
- **JS → Dart** (`source: 'careconnect-chime'`): `end-call-request`, `sentiment-transcript`,
  `sentiment-voice-metrics`, `sentiment-video-sample`, `sentiment-channel-state`; everything
  else is a log line.
- Transcript status and the SDK guard banner are driven by **string-matching log text** — fragile.
- SDK loads from `CHIME_SDK_URL` (default self-hosted `/amazon-chime-sdk.min.js`);
  external fallback is off in release.

### Step 9 — Live sentiment
**Patient is the only source. Caregiver is the only audience.** Absolute, both ends.

| Channel | Payload | Endpoint |
| --- | --- | --- |
| voice | `averageLevel`, `speechRatio`, `variability` (**no audio leaves the device**) | `POST /{callId}/sentiment/voice` |
| video | base64 JPEG frame | `POST /{callId}/sentiment/video` |
| transcript | text + speaker label | `POST /{callId}/transcript/segments` **via encrypted outbox** |

- Modes: `realtime` 6 s / `balanced` 15 s (default) / `adaptive`. Set by
  `CARECONNECT_SENTIMENT_MODE` at compile time.
- **Two independent rate limiters**: the iframe capture timer (fixed at construction) and the
  Dart upload throttle (`_sampleThrottleWindow`). Adaptive switching changes only the Dart side.
- `_shouldPrioritizeVoiceRecovery` bypasses the throttle when a quiet/degraded channel hears
  real speech again.
- Backend `ensureSentimentAllowedForCall` = `requireActiveParticipant` + `ensurePatientSource`
  (caregiver → **403**). Care-team is blocked client-side only.
- Silence short-circuit returns **202** with a QUIET channel-state push and records no score.
- `broadcastSentimentToCaregivers` → `sendSentimentToCaregiverIfEligible` filters to
  `Role.CAREGIVER` among **joined** participants.
- Client merge layer seeds `AWAITING`, clamps scores, and downgrades to `DEGRADED` after 45 s.
- Labels: `≥0.60 CALM`, `≥0.35 ANXIOUS`, else `DISTRESSED`.
- `/sentiment/text` exists but is **unreachable from the call screen** (no `onTextSend` passed).

### Step 10 — Recording starts (caregiver-only button)
`POST /{callId}/recording/start?consent=`

- `USER_PLAYBACK` (has a userId) **requires consent**; `SYSTEM_TRANSCRIPTION` (null userId) does not.
- `reserveActiveGeneration` is a conditional DB claim; losing it returns `POLICY_BLOCKED` to a
  human and `ALREADY_RECORDING` to the system.
- Pipeline: `sourceType CHIME_SDK_MEETING` → `sinkType S3_BUCKET`,
  `AudioMuxType.AUDIO_ONLY` + **video artifacts DISABLED** (composited view already has everyone).
- S3 key `recordings/{callId}/{utcTimestamp}/`.
- Then `startKvsPipelineAsync` binds each attendee to a KVS stream (`CallAttendee.kvsStreamArn`)
  — **required for post-call per-speaker transcription**.
- `notifyRecordingState` pushes to all joined participants → red consent banner for everyone.
- ⚠️ Start has **no** server-side role check (UI-gated only).

### Step 11 — Recording stops
`POST /{callId}/recording/stop`

- ⚠️ **Only the owner or an ADMIN may stop** — other caregivers get 403, but their button still
  renders and the client shows a generic "Failed to stop recording."
- 120-second stop lease (`claimForStop`); a 404 from `deleteMediaCapturePipeline` is success.
- Starts **concatenation** → single MP4. `STOPPED` ≠ playable; `playbackReady` is false here.
- Retryable statuses park `CallTerminationExecutor` before meeting teardown.

### Step 12 — Add participant (caregiver-only, server-enforced)
`GET /{callId}/eligible-invitees` → `POST /{callId}/invite`

- Eligible = the patient's other caregivers + family members, minus current participants.
  **Family members appear only here** — they can't start a call.
- A patient can never be added (`403 Cannot add a patient to an existing call`).
- Authorization is persisted **before** notifying.
- Offline invitee → SMS via `SnsService.publishSms` (160 chars, raw callId, no deep link).
- The dialog disables `pointerEvents` on **every iframe** in the document and restores on close.
- ⚠️ The patient is never asked to consent to a third party joining.

### Step 13 — An attendee leaves
`POST /{callId}/end` → `leaveOrBeginTermination`

```
remaining (joined, after marking self LEFT) > 1  → plain leave, call continues
remaining <= 1                                   → termination begins
```

**In a 1:1, either party hanging up ends the call for both.**

- `endCall()` force-flushes the transcript outbox first; so does `_handleRemoteCallEnd()`.
- `_completedCallIds` is a **static** process-wide fence → rejoin throws "This call has already ended."
  Only set when end status is `ended`/`processing`, not on a plain `left`.
- `call-ended` (200) vs `call-ending` (202) = whether the pipeline finished synchronously.
- ⚠️ **`participant-left` has no frontend handler anywhere in `frontend/lib`.**
- Browser-close does not end a call; EventBridge (`ChimeMediaStreamWebhookController`) reconciles
  the *roster* only — `CallTerminationReconciler` ends the session.

### Step 14 — Termination pipeline
`CallTerminationExecutor.execute` — four individually-fenced, resumable steps:

```
1 SENTIMENT  ensureFinalSentiment → analyzeFinalOverallSentiment
2 SUMMARY    generateAndStoreSummary  (dedup key: callId + transcriptSnapshotVersion + modelConfigVersion)
3 RECORDING  stopRecordingTyped — DEFERRED parks *before* meeting teardown
4 MEETING    ChimeService.endMeeting
   → completeTermination
```

Every step does `renewTerminationOwnership` before and `verifyTerminationOwnership` after; a
`null` means the lease was lost → return with no side effects.

Recovery: `CallTerminationReconciler` `@Scheduled` every 30 s (batch 25), plus a manual
`POST /{callId}/termination/reconcile`.

**Separate async tail** — `PostCallTranscriptionService`, `@Scheduled` every 20 s, deliberately
not `@Transactional`:
```
KVS fragments → KvsAudioTranscodeService.toWav → S3
  → one Transcribe job PER ATTENDEE, diarization OFF   ← the speaker-ID design
  → CallTranscriptSegment rows → summary regenerated → WAV/JSON scrubbed (PHI)
```

Speaker identity comes from **which KVS stream** the audio came from, not from diarization.

### Step 15 — Post-call
⚠️ **Nothing navigates you here.** `_exitCallScreen()` pops back / goes to `/dashboard`.

Reached from: `/calls/:callId/summary`, `CaregiverAnalyticsTab`, `PatientDetailsPage`.

`PostCallTelemetrySummaryScreen._loadTelemetry()` fires four calls in parallel:
`/telemetry`, `/summary`, `/transcript/segments`, `/recording`; plus lazy `/recording/playback-url`.

- **Regeneration on read**: a `NO_TRANSCRIPT` summary with segments now present is regenerated
  by the first person who opens it (`CallController:1038-1044`).
- Two access models: `requireDurableCallAccess` (summary/telemetry/transcript) vs
  `CallSessionService.requireRecordingAccess` (recording) — the latter admits a care-linked
  caregiver who never joined.
- `on_consent` visibility gate can 403 a caregiver who otherwise has access.
- Medication summary items re-run the Ask-AI safety pipeline and may route to Tier-2 HITL.
- Deletion endpoints are dev/local only. **No production data-deletion path.**

---

## 3. Endpoint reference

Base `/api/v3/calls`, Bearer auth.

| Method | Path | Step | Who |
| --- | --- | --- | --- |
| POST | `/sessions` | 4 | initiator |
| POST | `/{callId}/join` | 4-5 | both |
| GET | `/{callId}/eligible-invitees` | 12 | caregiver (enforced) |
| POST | `/{callId}/invite` | 12 | caregiver (enforced) |
| POST | `/{callId}/sentiment/text` | — | **unreachable from call screen** |
| POST | `/{callId}/sentiment/voice` | 9 | patient only (enforced) |
| POST | `/{callId}/sentiment/video` | 9 | patient only (enforced) |
| POST | `/{callId}/transcript/segments` | 9 | patient, via outbox |
| POST | `/{callId}/recording/start` | 10 | any participant (UI-gated to caregiver) |
| POST | `/{callId}/recording/stop` | 11 | **owner or ADMIN only** |
| GET | `/{callId}/recording` | 15 | `requireRecordingAccess` |
| GET | `/{callId}/recording/playback-url` | 15 | `requireRecordingAccess` |
| POST | `/{callId}/end` | 13 | both |
| POST | `/{callId}/termination/reconcile` | 14 | recovery |
| GET | `/{callId}/telemetry` | 15 | `requireDurableCallAccess` |
| GET | `/{callId}/summary` | 15 | + `on_consent` gate |
| POST | `/{callId}/summary/items/{itemId}/confirm` | 15 | |
| GET | `/{callId}/transcript/segments` | 15 | |

## 4. WebSocket message reference

**Client → server** (`CallNotificationHandler`):
`authenticate`, `join-user-room`, `send-video-call-invitation`, `send-sms-notification`,
`accept-call`, `decline-call`, `end-call` (**legacy no-op — logs and returns**), `heartbeat`,
`sentiment-channel-state`

**Server → client** (`CallNotificationService._processNotificationMessage`):

| Type | Handled? |
| --- | --- |
| `incoming-video-call` | ✅ popup |
| `call-invitation-sent` / `call-invitation-failed` | ✅ resolves the 8 s completer |
| `call-answered` | ✅ snackbar only |
| `call-declined` | ✅ snackbar + rejection screen |
| `call-ended` / `call-ending` | ✅ ejects |
| `call-invitation-cancelled` | ✅ dismiss |
| `sentiment-update` / `sentiment-channel-state` | ✅ caregiver dashboard |
| `recording-state` | ✅ banner |
| **`participant-left`** | ❌ **no handler** |

## 5. Role matrix

| Capability | Patient | Caregiver | Family member |
| --- | --- | --- | --- |
| Start a call | ✅ (if link enables it) | ✅ | ❌ |
| Be added to a call | ❌ (already the subject) | ✅ | ✅ |
| Sentiment captured from them | ✅ | ❌ | ❌ |
| See the sentiment dashboard | ❌ | ✅ | ❌ |
| Start / stop recording | ❌ (UI) | ✅ / owner only | ❌ |
| See the recording banner | ✅ | ✅ | ✅ |
| Add a participant | ❌ | ✅ | ❌ |
| Open the post-call summary | endpoint yes, **no UI path** | ✅ Analytics tab | — |

## 6. Key invariants

1. Every call is anchored to **exactly one patient** (`resolveCallSessionPatientUserId`).
2. Durable state is written **before** any AWS resource, and compensated on failure.
3. Chime `externalUserId` is opaque — never parse it for identity.
4. Exactly one node wins each election: recording-start, termination, stop lease, generation.
5. Sentiment is patient-sourced and caregiver-visible; never both, never neither.
6. `CARE_TEAM` disables sentiment, transcript capture, and the dashboard — client-side.
7. A summary is not final: it can be regenerated at termination, by the transcription worker,
   and again on first read.

## 7. Known gaps

| # | Gap | Where |
| --- | --- | --- |
| 1 | `participant-left` silently dropped — conference leaves invisible | `call_notification_service.dart:137-205` |
| 2 | Two dead entry points with full call UI | `presentation/pages/{caregiver,patient}_dashboard.dart` |
| 3 | Stop-recording button shown to non-owners; 403 shown as generic error | `hybrid_video_call_widget.dart:1593`, `:577` |
| 4 | Patient's recording banner stuck at `0:00` (timer only starts on button press) | `hybrid_video_call_widget.dart:563` |
| 5 | No patient-facing route to their own call summary | `app_router.dart:1034` |
| 6 | 8 s ring timeout; concurrent incoming popups silently suppressed | `call_notification_service.dart:571`, `:266` |
| 7 | N+1 sequential fetches in picker, repeated in permission check | `main_screen.dart:579`, `api_service.dart:485` |
| 8 | `FutureBuilder` future built in `build` → refetch on rebuild | `main_screen.dart:689` |
| 9 | Fallback detection by string-matching backend note text | `video_call_service.dart:873` |
| 10 | Transcript status derived from matching JS log strings | `chime_meeting_embed_web.dart:517` |
| 11 | Stray merge artifact `api_service.dart.main` with a diverging `canInitiateVideoCall` | `frontend/lib/services/` |

## 8. Debugging quick reference

| Symptom | Look at |
| --- | --- |
| Call screen loads black | `CHIME_SDK_URL` asset deployed? `_guardMessage`, `[CareConnect][Chime][error]` logs |
| No ring | Was `CallNotificationService.initialize()` called? Is the socket open? 8 s timeout? Another popup already visible? |
| "Not allowed to call X" | Often a token/500/timeout — `canInitiateVideoCall` returns false for every failure |
| Empty callee picker | Patient: `patientVideoCallsEnabled`. Caregiver: `caregiverId` null or non-200 → silent empty |
| No sentiment bars | Role resolution (`_isCaregiverView`), or `CARE_TEAM`, or patient socket down |
| Sentiment stuck `AWAITING` | Patient side not capturing — check `_isPatientView`, iframe mic permission |
| Recording won't stop | Owner check — only `ownerUserId` or ADMIN |
| Summary is empty | Opened before transcription landed; reopen (regeneration on read) |
| Call "ended" but peer still in it | `202 processing` — the reconciler finishes within ~30 s |

---

*Generated from a source trace of branch `fix/b-handoff-1.1.2-speaker-id-labels`.*

**Diagram:** `VIDEO_CALL_LIFECYCLE_DIAGRAM.html` — open in a browser. Interactive: light/dark,
three guided views (Phase rail / Live capture / Deferred artifacts), pan-zoom, search, export.
Regenerate after edits to `VIDEO_CALL_LIFECYCLE_DIAGRAM.json` with the `archify` skill:

```
node bin/archify.mjs deliver lifecycle \
  docs/guides/VIDEO_CALL_LIFECYCLE_DIAGRAM.json \
  docs/guides/VIDEO_CALL_LIFECYCLE_DIAGRAM.html --quality showcase
```
