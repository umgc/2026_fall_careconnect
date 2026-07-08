# Conference Call (Add Participant) — Implementation Guide

Caregivers can add care-circle members to an active Chime video call.

For local setup, API smoke tests, and ECS notes, see [TEAM_A_VIDEO_CALL_QUICKSTART.md](./TEAM_A_VIDEO_CALL_QUICKSTART.md).

## Overview

A caregiver in an active call can add another caregiver or a family member from the patient's care circle to the call. The invited person receives the same in-app popup that any incoming call triggers. Once they accept, they join the existing Chime meeting and their video tile appears automatically for all participants.

**Who can invite:** Caregiver only  
**Who can be invited:** Any CAREGIVER or FAMILY_MEMBER with an active link to the patient in the call  
**Who cannot be invited:** Another PATIENT  
**Sentiment analysis:** Unchanged — patient sentiment only, same as 1:1 calls

---

## Architecture (Pattern A)

Invite is **notify-only**. Chime `createAttendee` runs on **`POST /join`**, not on invite. This avoids duplicate attendees when the invitee accepts.

```
Caregiver taps "Add Participant"
  → Flutter: GET /api/v3/calls/{callId}/eligible-invitees
  ← Backend: returns care-circle members not already in call

Caregiver selects a person
  → Flutter: POST /api/v3/calls/{callId}/invite  { targetUserId }
  ← Backend: WebSocket "incoming-video-call" (isConferenceInvite: true) if invitee is online
           OR SMS via SnsService if invitee is offline and has a phone number on file
           (no createAttendee on invite)

Invitee sees "Joining Existing Call" popup
  → accepts → Flutter: POST /api/v3/calls/{callId}/join
  ← Backend: createAttendee() + cached join credentials (idempotent re-join)
  ← Chime SDK: new video tile appears for all participants automatically
```

### End-call and dismiss (3-party)

When the meeting ends (`POST /{callId}/end` with `shouldEndMeeting`):

- Backend notifies **all active participants** plus **pending invitees** (invited but never joined) via `call-ended` WebSocket.
- Frontend `call_notification_service.dart` dismisses any stale incoming-call popup for that `callId` on `call-ended` or `call-invitation-cancelled`.
- Flutter sends `participantUserIds` in the end-call body so the server can merge roster for notify/leave logic.

---

## Files Changed

### Backend

| File | Change |
|------|--------|
| [CallController.java](../../backend/core/src/main/java/com/careconnect/controller/CallController.java) | `GET /eligible-invitees`, `POST /invite` (notify-only), `resolveNotifyUserIds`, `resolvePendingInviteeIds`, offline SMS (`maybeSendOfflineConferenceInviteSms`), end-call broadcast |
| [ChimeService.java](../../backend/core/src/main/java/com/careconnect/service/ChimeService.java) | In-memory join credential cache; cleared on `endMeeting` |

### Frontend

| File | Change |
|------|--------|
| [video_call_service.dart](../../frontend/lib/services/video_call_service.dart) | `getEligibleInvitees`, `inviteParticipant`, `trackParticipant`, `participantUserIds` in end body |
| [call_notification_service.dart](../../frontend/lib/services/call_notification_service.dart) | `isConferenceInvite` popup; dismiss on `call-ended` / `call-invitation-cancelled` |
| [incoming_call_popup.dart](../../frontend/lib/widgets/incoming_call_popup.dart) | "Joining Existing Call" UI for conference invites |
| [hybrid_video_call_widget.dart](../../frontend/lib/widgets/hybrid_video_call_widget.dart) | Caregiver `person_add` invite flow; participant tracking |
| [chime_meeting_embed_web.dart](../../frontend/lib/widgets/chime_meeting_embed_web.dart) | Multi-tile scrollable video grid |
| [chime_meeting_embed_mobile.dart](../../frontend/lib/widgets/chime_meeting_embed_mobile.dart) | Same multi-tile grid in WebView (Android/iOS) |

---

## API Reference

### GET `/api/v3/calls/{callId}/eligible-invitees`

**Auth:** JWT — CAREGIVER role required  
**Returns:** Array of inviteable care-circle members

```json
[
  { "userId": 42, "name": "Dr. Patel", "role": "CAREGIVER", "relationship": null },
  { "userId": 87, "name": "Maria Santos", "role": "FAMILY_MEMBER", "relationship": "Daughter" }
]
```

**Errors:**
- `403` — caller is not a CAREGIVER
- `410` — meeting is no longer active
- `404` — no patient found in the call's telemetry

### POST `/api/v3/calls/{callId}/invite`

**Auth:** JWT — CAREGIVER role required  
**Body:** `{ "targetUserId": 42 }`  
**Returns:** `{ "status": "invited", "callId": "...", "targetUserId": 42 }`

**Errors:**
- `403` — caller is not a CAREGIVER, or target is a PATIENT, or target has no active link to this patient
- `410` — meeting is no longer active
- `404` — user not found / no patient in call

**Side effects:**

- Does **not** call Chime `createAttendee` — invitee is added on `POST /join` only
- If target is **online:** sends `incoming-video-call` with `isConferenceInvite: true`
- If target is **offline** and has `User.phone` set: sends conference-invite **SMS** via `SnsService`
- Records `CONFERENCE_INVITE` telemetry (`STATUS_SUCCESS` or `OFFLINE`)

### POST `/api/v3/calls/{callId}/join`

Unchanged route; creates attendee credentials (with in-memory cache for idempotent re-join).

### POST `/api/v3/calls/{callId}/end`

When the meeting is fully ended, notifies all participants and pending invitees. Optional body may include `participantUserIds` (array of user IDs) from the client roster.

---

## Chime Video Grid (web + mobile)

Previous layout used a single `<video id="remoteVideo">` (one remote at a time). Both embeds now use a dynamic grid:

- `#videoGridScroll` — scrollable container
- `#videoGrid` — CSS grid; one `<video class="remote-video">` per remote tile
- `remoteTiles` Map in embed JS — `videoTileDidUpdate` / `videoTileWasRemoved`
- Column count computed from participant count and viewport width; last-row orphan spans full width
- Local PiP (`#localVideo`) unchanged
- **7+ remotes:** vertical scroll (`layout-scroll`)

No Flutter-side tile management — Chime SDK signaling drives tile add/remove.

---

## Deployment note (ECS)

`ChimeService` caches join credentials **in memory per JVM**. WebSocket call notifications are also in-memory per instance.

For dev/demo Fargate stacks, keep **`DesiredCount: 1`** on the ECS service so invite/join cache and WS sessions stay on one task. Multi-task scaling requires sticky sessions or a shared cache (not implemented yet).

CloudFormation parameters already default to `DesiredCount: 1` in `cloudformation-fargate/parameters/*-service.json`.

---

## Known Limitations

### FCM / push (not implemented)

SMS covers offline conference invite when a phone number exists. **FCM push** for users without SMS is not wired into call flows yet.

### Multi-task ECS

Join credential cache and WebSocket routing are not shared across ECS tasks. Do not scale the call-facing service above one task without stickiness or Redis.

### Maximum participants (visual)

AWS Chime supports many attendees. The grid scrolls for large N; layout is optimized for 1 patient + 2–3 caregivers/family.

### Sentiment

Conference video works for all parties; Bedrock sentiment monitoring remains **patient-only** (same as 1:1 calls).

---

## Testing Checklist

### Automated

```powershell
cd backend\core
.\mvnw.cmd test -Dtest="CallControllerTest,CallFlowIntegrationTest,ChimeServiceTest,CallNotificationHandlerTest" --batch-mode

cd frontend
flutter test test/video_call/ test/services/hybrid_video_call_service_test.dart test/widgets/incoming_call_popup_test.dart test/services/call_notification_service_test.dart
```

### Manual (3-party)

- [ ] Caregiver sees `person_add`; patient does not
- [ ] Online invitee gets "Joining Existing Call" popup
- [ ] Offline invitee with phone gets SMS (SNS configured)
- [ ] Accepted invitee joins; each remote gets a tile (web + mobile)
- [ ] Grid resizes with participant count; scrolls when many remotes
- [ ] End call dismisses popup for pending invitees; all parties disconnect
- [ ] Re-join same call returns cached credentials (no duplicate attendee)
- [ ] Sentiment still tracks patient only

**Dev logins** (mock data): `patient@careconnect.com`, `caregiver@careconnect.com`, `family@careconnect.com` — password `password`.
