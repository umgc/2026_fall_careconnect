# Team A Quickstart: Chime Video Calling + Bedrock Sentiment + Call Recording + Speaker ID

This guide covers:
- Chime video call join/end flow
- Bedrock sentiment APIs (text, voice, video, combined)
- Call recording via AWS Chime Media Capture Pipelines → S3
- Speaker identification (per-attendee KVS → WAV → Transcribe)
- Minimal navigation path to test quickly

Deploy / IAM for Fargate: see [cloudformation-fargate/README.md](../../cloudformation-fargate/README.md)
(sections **ECS task role permissions** and **KVS speaker stream pool**).

## 1) Where to run from

- Backend path: `backend/core`
- Frontend path: `frontend`

## 2) Start backend (Windows)

Open PowerShell in `backend/core` and run:

```text
mvnw.cmd spring-boot:run -Dspring.profiles.active=dev
```

If you use local env files first:

```text
load-env.bat
mvnw.cmd spring-boot:run -Dspring.profiles.active=dev
```

Backend health/docs:
- http://localhost:8080/actuator/health
- http://localhost:8080/swagger-ui.html

## 3) Backend env vars needed for your feature

Copy the env template, then edit secrets:

```text
cd backend/core
copy .env.example .env
```

(`cp .env.example .env` on macOS/Linux.) Load with `load-env.bat` / `run-dev-win.bat`, or rely on
`spring.config.import=optional:file:.env[.properties]` in the `dev` profile.

Minimum for auth/login:
- `JDBC_URI`
- `DB_USER`
- `DB_PASSWORD`
- `SECURITY_JWT_SECRET`

### Local AWS credentials (required for Chime / recording / speaker ID)

Local `dev` does **not** use the ECS task role. Put real keys in `.env`:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION` / `AWS_REGION` (for example `us-east-1`)

Those keys must belong to an **IAM user** that has the policy in **§3a** (attach the policy
to a **group**, then add every developer to that group). Without that, Chime join, recording,
KVS speaker ingest, Bedrock sentiment, and Transcribe fail with access errors even when
feature flags are on.

Optional model overrides: `aws.bedrock.sentiment.model-id`, `aws.bedrock.voice.model-id`

### 3a) IAM policy for local developers (group setup)

Mirror of [`cloudformation-fargate/templates/03-platform.yaml`](../../cloudformation-fargate/templates/03-platform.yaml)
`EcsTaskRole` app policy, adapted for **shared local IAM users** (wildcard account / region
where CFN used stack parameters). Prefer one **managed policy** on one **IAM group** so you
do not edit each user.

#### Create the group and attach the policy (AWS Console)

1. **IAM → Policies → Create policy → JSON**. Paste the document below. Name it e.g.
   `CareConnectLocalDevVideoCalling`.
2. **IAM → User groups → Create group**. Name it e.g. `careconnect-local-dev`.
3. Attach `CareConnectLocalDevVideoCalling` to that group.
4. **Add users** to the group (existing teammates or new IAM users).
5. For each user: **Security credentials → Create access key** (CLI / local code). Put the
   key id + secret in that developer’s `backend/core/.env` (never commit).

#### Same via AWS CLI (optional)

```bash
# 1) Save the JSON below as careconnect-local-dev-policy.json, then:
aws iam create-policy \
  --policy-name CareConnectLocalDevVideoCalling \
  --policy-document file://careconnect-local-dev-policy.json

# 2) Group + attach (replace ACCOUNT_ID with your 12-digit account id)
aws iam create-group --group-name careconnect-local-dev
aws iam attach-group-policy \
  --group-name careconnect-local-dev \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/CareConnectLocalDevVideoCalling

# 3) Add each developer
aws iam add-user-to-group --group-name careconnect-local-dev --user-name Alice
```

#### Policy JSON (full layout)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ChimeMeetings",
      "Effect": "Allow",
      "Action": [
        "chime:CreateMeeting",
        "chime:DeleteMeeting",
        "chime:GetMeeting",
        "chime:ListMeetings",
        "chime:CreateAttendee",
        "chime:DeleteAttendee",
        "chime:GetAttendee",
        "chime:ListAttendees",
        "chime:StartMeetingTranscription",
        "chime:StopMeetingTranscription",
        "chime:GetMeetingTranscriptionStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ChimeMediaPipelines",
      "Effect": "Allow",
      "Action": [
        "chime:CreateMediaCapturePipeline",
        "chime:CreateMediaConcatenationPipeline",
        "chime:DeleteMediaCapturePipeline",
        "chime:DeleteMediaPipeline",
        "chime:GetMediaCapturePipeline",
        "chime:GetMediaPipeline",
        "chime:CreateMediaStreamPipeline"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KinesisVideoStreams",
      "Effect": "Allow",
      "Action": [
        "kinesisvideo:DescribeStream",
        "kinesisvideo:GetDataEndpoint",
        "kinesisvideo:GetMedia",
        "kinesisvideo:GetMediaForFragmentList",
        "kinesisvideo:ListStreams",
        "kinesisvideo:ListFragments"
      ],
      "Resource": "arn:aws:kinesisvideo:*:*:stream/*"
    },
    {
      "Sid": "S3CareConnectBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutBucketPolicy",
        "s3:PutBucketCors",
        "s3:GetBucketAcl",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::careconnect-recordings-*",
        "arn:aws:s3:::careconnect-recordings-*/*",
        "arn:aws:s3:::careconnect-uploads-*",
        "arn:aws:s3:::careconnect-uploads-*/*"
      ]
    },
    {
      "Sid": "BedrockInvoke",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TranscribeJobs",
      "Effect": "Allow",
      "Action": [
        "transcribe:StartTranscriptionJob",
        "transcribe:GetTranscriptionJob",
        "transcribe:DeleteTranscriptionJob",
        "transcribe:ListTranscriptionJobs"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TextractOcr",
      "Effect": "Allow",
      "Action": [
        "textract:StartDocumentTextDetection",
        "textract:GetDocumentTextDetection",
        "textract:DetectDocumentText"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Notifications",
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail",
        "sns:Publish"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SsmParameters",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/careconnect/*"
    },
    {
      "Sid": "KmsDecryptViaSsm",
      "Effect": "Allow",
      "Action": ["kms:Decrypt"],
      "Resource": "arn:aws:kms:*:*:key/*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "ssm.us-east-1.amazonaws.com",
            "ssm.us-west-2.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "IamChimeMediaPipelinesServiceLinkedRole",
      "Effect": "Allow",
      "Action": ["iam:CreateServiceLinkedRole"],
      "Resource": "arn:aws:iam::*:role/aws-service-role/mediapipelines.chime.amazonaws.com/*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": "mediapipelines.chime.amazonaws.com"
        }
      }
    },
    {
      "Sid": "StsGetCallerIdentity",
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    },
    {
      "Sid": "EventBridgeLocalKvsWireOptional",
      "Effect": "Allow",
      "Action": [
        "events:CreateConnection",
        "events:UpdateConnection",
        "events:DescribeConnection",
        "events:ListConnections",
        "events:CreateApiDestination",
        "events:UpdateApiDestination",
        "events:DescribeApiDestination",
        "events:PutRule",
        "events:PutTargets",
        "events:DescribeRule",
        "events:ListTargetsByRule",
        "iam:CreateRole",
        "iam:GetRole",
        "iam:PutRolePolicy",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

Notes:
- **Chime / Bedrock / Transcribe** often need console one-time enablement (model access,
  service-linked roles) in addition to this IAM policy.
- The last statement (`EventBridgeLocalKvsWireOptional`) is only needed for developers who
  run `backend/core/scripts/wire-chime-kvs-eventbridge-local.ps1`. You can omit it from the
  shared group and grant it to one admin if preferred.
- ECS production uses the task role in CFN — do **not** put these access keys on Fargate.

### Call recording (opt-in in `application.properties`)

Default in `application.properties`: `careconnect.recording.enabled=false`
(`CARECONNECT_RECORDING_ENABLED` unset → off). Local `application-dev.properties` turns
recording **on**. For a custom env file, set:

- `CARECONNECT_RECORDING_ENABLED=true`

Post-call speaker transcription is triggered from the recording lifecycle (concatenated
video ready). Speaker ID ingest alone is not enough without recording enabled.

### Speaker ID / KVS (opt-in locally; on in ECS)

Default in `application.properties`: `careconnect.kvs.enabled=false`
(`CARECONNECT_KVS_ENABLED` unset → off). A plain local run does **not** start stream
pipelines until you opt in. ECS sets `CARECONNECT_KVS_ENABLED=true` via
`cloudformation-fargate/templates/04-service.yaml`.

For local speaker-ID testing, set in `.env` (see `.env.example`):

- `CARECONNECT_KVS_ENABLED=true`
- `CARECONNECT_KVS_STREAM_POOL_ARN=<Chime KVS stream pool ARN>`
- `CARECONNECT_KVS_EVENT_WEBHOOK_ENABLED=true` — **required for reliable local discovery**
  (EventBridge → ngrok → laptop; see **§7b** / **§7c**)
- `CARECONNECT_KVS_EVENT_WEBHOOK_SHARED_SECRET` — must match EventBridge connection
  `ApiKeyValue` (local wire script uses `local-dev`; ECS uses `careconnect-${Environment}-kvs-discovery`)

Optional: `CARECONNECT_KVS_STREAM_DISCOVERY_TIMEOUT_MS` (default 60000).

Notes:
- On ECS Fargate, use the **task role** (no static AWS keys in the task).
- Locally, use the **IAM group / user** from §3a — not the ECS task role ARN.

## 4) Start frontend

Open a second terminal in frontend and run:

flutter pub get
flutter run -d chrome --web-port=50030 --dart-define=BACKEND_URL=http://localhost:8081

(Use your preferred device instead of chrome if needed. Adjust the port to match your local backend.)

## 5) How to navigate the app (first time)

1. Open app root and go to Login.
2. Log in with an account in your local DB.
3. You should land on /dashboard.
4. For direct Team A testing, use this route in browser:

/#/video-call-chime?userId=1&recipientId=2&userName=Caregiver&recipientName=Patient&initiator=true&video=true&audio=true

What this does:
- Opens HybridVideoCallWidget (Team A path)
- Calls backend /api/v3/calls/{callId}/join
- Uses call sentiment panel (text + periodic combined flow)

## 6) API endpoints in your scope

Base: /api/v3/calls
- POST /{callId}/join
- POST /{callId}/end
- POST /{callId}/sentiment/text
- POST /{callId}/sentiment/voice
- POST /{callId}/sentiment/video
- POST /{callId}/sentiment/combined
- GET  /{callId}/telemetry
- GET  /telemetry/my
- GET  /sentiment-history?userId={id}
- POST /{callId}/recording/start
- POST /{callId}/recording/stop
- GET  /{callId}/recording
- GET  /{callId}/recording/playback-url
- DELETE /recordings  (dev/local only — purges all recordings from S3 + DB)

## 7) Call recording setup

Recording defaults to OFF in `application.properties`. Local `dev` profile enables it;
otherwise set `CARECONNECT_RECORDING_ENABLED=true`.

1. Confirm recording is enabled (dev properties or env).

2. Ensure your **local IAM user** has recording permissions (see section 3). At minimum:

   ```text
   iam:CreateServiceLinkedRole
     Resource: arn:aws:iam::*:role/aws-service-role/mediapipelines.chime.amazonaws.com/*

   s3:CreateBucket, s3:PutBucketPolicy, s3:PutBucketCors, s3:PutObject, s3:GetObject,
   s3:ListBucket, s3:DeleteObject
     Resource: arn:aws:s3:::careconnect-recordings-*
               (and :::careconnect-recordings-*/* for object actions)

   chime:CreateMediaCapturePipeline, chime:DeleteMediaCapturePipeline,
   chime:GetMediaCapturePipeline, chime:CreateMediaConcatenationPipeline,
   chime:GetMediaPipeline, chime:DeleteMediaPipeline
     Resource: *
   ```

3. Everything else is automatic:
   - The S3 bucket (careconnect-recordings-{accountId}-{region}) is created at startup if absent.
   - The Chime bucket policy is applied at startup on every run (idempotent).
   - Recording bucket CORS (for §3.3 sentiment clip seek on web) is applied at startup if `s3:PutBucketCors` is allowed.
   - The IAM service-linked role AWSServiceRoleForAmazonChimeSDKMediaPipelines is created at
     startup if absent, provided iam:CreateServiceLinkedRole is in your policy.

   IF iam:CreateServiceLinkedRole cannot be added to your user policy, run this once manually
   (any team member, any machine — one-time per AWS account):

     aws iam create-service-linked-role --aws-service-name mediapipelines.chime.amazonaws.com

   IF `s3:PutBucketCors` cannot be added to your dev user, apply CORS once manually (admin or bucket owner):

     aws s3api put-bucket-cors --bucket careconnect-recordings-<accountId>-<region> --cors-configuration file://scripts/recording-bucket-cors.json

   Example (us-east-1 account 946509368247):

     cd backend/core
     aws s3api put-bucket-cors --bucket careconnect-recordings-946509368247-us-east-1 --cors-configuration file://scripts/recording-bucket-cors.json

   For shared/prod buckets, set `careconnect.recording.cors-allow-wildcard=false` (or env
   `CARECONNECT_RECORDING_CORS_ALLOW_WILDCARD=false`) and list explicit Amplify origins in
   `careconnect.cors_allowed` instead of `*`.

4. To clean up test recordings after a session, tap "Delete Call History (Dev)" in the patient
   details screen. This wipes all S3 objects under the recordings/ prefix AND all DB records.

## 7b) Speaker identification (KVS) setup — local

**Path:** 2nd participant join → `CreateMediaStreamPipeline` (IndividualAudio → Chime KVS
stream pool) → EventBridge (or polling fallback) maps attendee → stream ARN → after call,
assemble archived fragments → ffmpeg WAV → Amazon Transcribe per attendee (role-labeled
segments). Mixed MP4 Transcribe remains the fallback / supplemental path.

**Local opt-in:** leave KVS off unless you are testing speaker ID. When testing:

1. Create (or reuse) a Chime KVS stream pool in `us-east-1` and set
   `CARECONNECT_KVS_STREAM_POOL_ARN` to its ARN in `.env`.
2. Set `CARECONNECT_KVS_ENABLED=true` and keep `CARECONNECT_RECORDING_ENABLED=true`
   (recording lifecycle triggers post-call transcription).
3. Confirm your IAM user is in the **§3a** group (KVS + stream-pipeline actions).
4. Expose the backend with **ngrok** and enable the webhook (§7c), then set
   `CARECONNECT_KVS_EVENT_WEBHOOK_ENABLED=true`.
5. Wire EventBridge once (or when the public URL changes):

   ```powershell
   cd backend\core
   .\scripts\wire-chime-kvs-eventbridge-local.ps1 -NgrokBaseUrl https://YOUR-STABLE-SUBDOMAIN.ngrok-free.app
   ```

6. Confirm `ffmpeg` is on `PATH` (Docker image installs it for ECS; local Windows/macOS
   need a local install for KVS → WAV).

**Smoke check:** 2-party call with speech on both sides → logs register KVS streams → DB
`call_recordings.media_stream_pipeline_id` and `call_attendees.kvs_stream_arn` set →
post-call transcript segments with Caregiver/Patient (or role) labels.

**Short / partial calls:** If only some attendee streams yield Transcribe text (for example
a very short call), the app keeps those KVS segments and may run a **supplemental** full-call
MP4 job. That is expected, not a full primary success.

**Deploy:** see [cloudformation-fargate/README.md](../../cloudformation-fargate/README.md)
§ KVS speaker stream pool. ECS turns KVS + EventBridge webhook on; you still must put a
real pool ARN in SSM (recording is enabled on the task definition).

## 7c) ngrok setup (stable URL for EventBridge)

EventBridge must POST to a **public HTTPS** URL that reaches your laptop
(`POST /api/internal/chime/media-stream-events`). ngrok provides that tunnel.

### Account and install

1. Create a free account at [https://dashboard.ngrok.com/signup](https://dashboard.ngrok.com/signup).
2. Install the ngrok agent ([https://ngrok.com/download](https://ngrok.com/download)) or
   `winget install ngrok.ngrok` / `brew install ngrok`.
3. Copy your **authtoken** from the ngrok dashboard → **Your Authtoken**.
4. Log the agent in once (stores the token on this machine):

   ```text
   ngrok config add-authtoken <YOUR_AUTHTOKEN>
   ```

   After this, you stay logged in across restarts of the agent / PC (token is in the local
   ngrok config). You do **not** re-paste the token every day.

### Stable public URL (does not change on every restart)

Anonymous / unpaid random tunnels get a **new** hostname every time you run `ngrok http`,
which forces you to re-run the EventBridge wire script.

With a logged-in free account you can reserve a **static domain** (dashboard → **Domains**
→ claim a free `*.ngrok-free.app` subdomain). Then always start:

```text
ngrok http 8080 --url=https://YOUR-STABLE-SUBDOMAIN.ngrok-free.app
```

(Or set that domain as the default endpoint in the ngrok agent config.)

**Result:** as long as you are logged in with the authtoken and use the same reserved
domain, the public base URL **stays the same** across ngrok restarts. You only re-run
`wire-chime-kvs-eventbridge-local.ps1` if you change the reserved domain or the API path.

Without a reserved domain, `ngrok http 8080` still works while logged in, but the URL may
change each session — update EventBridge whenever it does.

### Wire EventBridge to that URL

Backend must be listening on port **8080** (or change both ngrok and the script). Then:

```powershell
.\scripts\wire-chime-kvs-eventbridge-local.ps1 -NgrokBaseUrl https://YOUR-STABLE-SUBDOMAIN.ngrok-free.app
```

Ensure `.env` has `CARECONNECT_KVS_EVENT_WEBHOOK_ENABLED=true` and
`CARECONNECT_KVS_EVENT_WEBHOOK_SHARED_SECRET=local-dev` (must match the wire script
`ApiKeyValue`), then restart the backend.

**Security:** ngrok exposes this webhook on the public internet. The shared secret in
`X-EventBridge-Connection` is required — do not leave it blank, and do not commit
production secrets.

Quick probe (should return empty/200; must include the auth header). In PowerShell use
`Invoke-RestMethod` (plain `curl` is aliased to `Invoke-WebRequest`):

```powershell
Invoke-RestMethod -Method POST `
  -Uri "https://YOUR-STABLE-SUBDOMAIN.ngrok-free.app/api/internal/chime/media-stream-events" `
  -Headers @{ "X-EventBridge-Connection" = "local-dev" } `
  -ContentType "application/json" `
  -Body '{"detail":{}}'
```

## 8) Fast troubleshooting

If call screen opens but fails immediately:
- Verify you are logged in (JWT exists in app storage).
- Verify backend is running on localhost:8080.
- Verify AWS credentials/role and region — local needs a working **IAM user**, not ECS task role.

If sentiment calls fail:
- Check backend logs for Bedrock invoke errors.
- Validate IAM permission `bedrock:InvokeModel` on your local IAM user.

If Chime join fails:
- Check backend logs for `chime:*` permissions and region mismatch.

If recording fails with "service-linked role" error:
- Add `iam:CreateServiceLinkedRole` to your IAM user policy (see section 7 above), or
- Run: `aws iam create-service-linked-role --aws-service-name mediapipelines.chime.amazonaws.com`
- Restart the backend — it provisions the role at startup automatically.

If recording fails with "bucket policy does not exist":
- This should never happen after the startup provisioning was added.
- If it does, restart the backend — policy is re-applied on every start.

If speaker ID falls back to mixed MP4 / no role labels:
- Confirm `CARECONNECT_KVS_ENABLED=true` and a valid `CARECONNECT_KVS_STREAM_POOL_ARN`.
- Confirm local IAM includes Kinesis Video fragment APIs and `chime:CreateMediaStreamPipeline` (§3a).
- Locally, prefer EventBridge + ngrok (§7c); do not rely on KVS polling alone.
- If the ngrok URL changed (no reserved domain), re-run `wire-chime-kvs-eventbridge-local.ps1`.
- Confirm recording ran (system or claimed) so post-call transcription can start.

## 9) ECS Fargate path (parallel, minimal coupling)

Terraform module added at:
- terraform_aws/5_ecs_fargate

Local syntax check already passes:
- terraform init -backend=false
- terraform validate

For team integration later, keep this module parallel and avoid touching shared migration work unless requested.

**Conference / Chime note:** `ChimeService` join-credential cache and `CallNotificationHandler` WebSocket sessions are **in-memory per JVM**. For Fargate dev/demo, keep the backend ECS service at **`DesiredCount: 1`** (already the default in `cloudformation-fargate/parameters/*-service.json`). Scaling out requires sticky sessions or a distributed cache — not implemented in this repo yet.

---

## 10) Automated Testing

### Test suite overview

All tests are scoped to the video calling feature. The suite covers all 21 TDD test IDs
(CALL-001/016/017/018/019, CHIME-001 through CHIME-009, SENT-001 through SENT-007).

| Layer | Files | Count | What it tests |
|-------|-------|-------|---------------|
| Backend unit | CallControllerTest.java | 24 | REST endpoint behavior, auth, sentiment POST routes |
| Backend unit | CallControllerExtendedTest.java | 35 | Recording endpoints, combined sentiment, transcript, delete routes |
| Backend unit | BedrockSentimentServiceTest.java | 22 | Heuristic scoring, voice/video/combined fallback |
| Backend unit | CallTelemetryServiceTest.java | 16 | Event recording, sanitization, sentiment retrieval |
| Backend unit | CallTelemetryServiceExtendedTest.java | 29 | getSentimentHistoryForUser, summarizeCall, WebSocket events, sanitizePayload |
| Backend unit | CallPermissionServiceTest.java | 15 | CALL-016/017/019 link-based permission rules |
| Backend unit | CallNotificationHandlerTest.java | 18 | WebSocket handlers: auth, join, call invite, CALL-016/017, heartbeat |
| Backend unit | CallRecordingServiceTest.java | 29 | Recording start/stop/status/playback-url/purge with AWS mock |
| Backend unit | ChimeServiceTest.java | 24 | Local mode, AWS mode, transcription, idempotency |
| Backend unit | CaregiverPatientLinkServiceExtendedTest.java | 27 | createLink, updateLink, suspend/reactivate/revoke, setVideoCallsEnabled |
| Backend integration | CallFlowIntegrationTest.java | 19 | Full call lifecycle: join → sentiment → end → telemetry |
| Frontend unit | video_call_service_test.dart | 27 | Service state machine, guards, constants |
| Frontend unit | hybrid_video_call_widget_test.dart | 16 | Widget build/render for all roles and error states |
| Frontend E2E | video_call_e2e_test.dart | 10 | App launch, login, sentiment panel visibility, end-call |

Total: **296 automated tests, 0 failures**

### Running backend tests (no database needed)

From backend/core:

    mvnw.cmd test -Dtest="CallControllerTest,CallControllerExtendedTest,BedrockSentimentServiceTest,CallTelemetryServiceTest,CallTelemetryServiceExtendedTest,CallPermissionServiceTest,CallNotificationHandlerTest,CallRecordingServiceTest,ChimeServiceTest,CaregiverPatientLinkServiceExtendedTest,CallFlowIntegrationTest" --no-transfer-progress

The integration test uses H2 in-memory (application-test.properties). No AWS credentials,
no PostgreSQL, and no running services required. All AWS SDK calls are mocked.

Expected output:

    Tests run: 252, Failures: 0, Errors: 0, Skipped: 0
    BUILD SUCCESS

### Backend coverage report (JaCoCo)

JaCoCo is wired into the `test` phase — the HTML report generates automatically every time
you run tests. No extra command needed.

Report location:

    backend/core/target/site/jacoco/index.html

Open it:

    # Windows PowerShell
    start backend\core\target\site\jacoco\index.html

The report shows line, branch, and method coverage broken down by package and class.
Drill into `com.careconnect.controller`, `com.careconnect.service`, and
`com.careconnect.websocket` for the video-call feature coverage.

Current instruction coverage for video-call feature classes:

| Class | Coverage | Notes |
|-------|----------|-------|
| ChimeService | 88% | Local mode + AWS mode + transcription |
| CaregiverPatientLinkService | 86% | All link CRUD + permission methods |
| CallTelemetryService | 86% | Full event recording + sentiment history |
| CallRecordingService | 74% | Start/stop/status/playback/purge |
| CallController | 71% | All 20+ endpoints including recording |
| CallNotificationHandler | 66% | All 8 WebSocket handlers |
| BedrockSentimentService | 43% | Heuristic + voice/video/combined |

Note: SonarQube is also configured in pom.xml (sonar-maven-plugin + sonar.* properties)
and reads the same JaCoCo exec file. SonarQube analysis runs in CI and requires a server
URL + token — it is not needed for local development.

### Running frontend unit tests (no device needed)

From frontend/:

    flutter test test/video_call/

Expected output (43 tests):

    All tests passed!

### Running frontend E2E / integration tests (requires device or emulator)

From frontend/:

    flutter test integration_test/video_call_e2e_test.dart -d chrome

Or with a connected device:

    flutter test integration_test/video_call_e2e_test.dart

Note: E2E tests exercise real navigation flows. They pass gracefully when the
backend is unreachable — call/sentiment tests degrade to error-state verification.

### TDD coverage matrix (all 21 IDs)

| TDD ID | Scenario | Primary test |
|--------|----------|-------------|
| CALL-001 | Caregiver → assigned patient: SUCCESS | CallFlowIntegrationTest, CallControllerTest |
| CALL-016 | Patient → unassigned caregiver: BLOCKED | CallPermissionServiceTest, CallNotificationHandlerTest |
| CALL-017 | Patient → patient: BLOCKED | CallPermissionServiceTest, CallNotificationHandlerTest |
| CALL-018 | Patient → assigned caregiver: SUCCESS | CallFlowIntegrationTest, CallControllerTest |
| CALL-019 | Caregiver → caregiver: SUCCESS | CallPermissionServiceTest |
| CHIME-001 | Meeting created on CALL_ACCEPT | CallFlowIntegrationTest, CallControllerTest, ChimeServiceTest |
| CHIME-002 | Attendee credentials generated | CallFlowIntegrationTest, ChimeServiceTest |
| CHIME-003 | Unauthenticated request blocked | CallFlowIntegrationTest, CallControllerTest |
| CHIME-004 | Client joins with credentials | CallFlowIntegrationTest, ChimeServiceTest |
| CHIME-005 | SDK exception → 500 | CallControllerTest, ChimeServiceTest |
| CHIME-006 | Call ends cleanly, metadata persisted | CallFlowIntegrationTest, CallControllerTest, ChimeServiceTest |
| CHIME-007 | SRTP via AWS SDK (no custom crypto) | CallPermissionServiceTest, ChimeServiceTest |
| CHIME-008 | AppException re-thrown on error | CallControllerTest |
| CHIME-009 | Second join same callId is idempotent | CallFlowIntegrationTest, ChimeServiceTest |
| SENT-001 | Live sentiment streamed during call | All backend tests + video_call_service_test |
| SENT-002 | Sentiment panel visible for caregivers | hybrid_video_call_widget_test, video_call_e2e_test |
| SENT-003 | Latency < P95 (500ms local heuristic) | BedrockSentimentServiceTest |
| SENT-004 | End-of-call summary generated | CallFlowIntegrationTest, CallControllerExtendedTest |
| SENT-005 | Sentiment persisted + retrievable | CallFlowIntegrationTest, CallTelemetryServiceExtendedTest |
| SENT-006 | Caregiver blocked from submitting sentiment | CallFlowIntegrationTest, CallControllerExtendedTest |
| SENT-007 | Sentiment service down → call continues | BedrockSentimentServiceTest, CallFlowIntegrationTest |

### Call permission enforcement (CALL-016/017)

CALL-016 (patient → unassigned caregiver) and CALL-017 (patient → patient) are
enforced at the WebSocket layer in CallNotificationHandler.handleCallInvitation():

- PATIENT → PATIENT: sends `call-invitation-failed` immediately (added in this branch)
- PATIENT → CAREGIVER (no link): sends `call-invitation-failed` with reason
  "No active caregiver-patient link"
- Service layer: CaregiverPatientLinkService.hasAccessToPatient() backs the check

This enforcement runs before any Chime meeting is created, so no AWS call is made
for blocked call attempts.

Both scenarios are now tested at two layers:
- `CallPermissionServiceTest` — pure unit tests of the service logic
- `CallNotificationHandlerTest` — WebSocket handler tests verifying the `call-invitation-failed`
  response message is sent with the correct reason string
