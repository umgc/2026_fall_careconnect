# Team A Quickstart: Chime Video Calling + Bedrock Sentiment + Call Recording

This guide is for your current feature branch and focuses only on your scope:
- Chime video call join/end flow
- Bedrock sentiment APIs (text, voice, video, combined)
- Call recording via AWS Chime Media Capture Pipelines → S3
- Minimal navigation path to test quickly

## 1) Where to run from

- Repo path: D:/dev/2026_spring_careconnect
- Backend path: D:/dev/2026_spring_careconnect/backend/core
- Frontend path: D:/dev/2026_spring_careconnect/frontend

## 2) Start backend (Windows)

Open PowerShell in backend/core and run:

mvnw.cmd spring-boot:run -Dspring.profiles.active=dev

If you use local env files first:

load-env.bat
mvnw.cmd spring-boot:run -Dspring.profiles.active=dev

Backend health/docs:
- http://localhost:8080/actuator/health
- http://localhost:8080/swagger-ui.html

## 3) Backend env vars needed for your feature

Minimum for auth/login:
- JDBC_URI
- DB_USER
- DB_PASSWORD
- SECURITY_JWT_SECRET

For Chime + Bedrock feature path:
- AWS_DEFAULT_REGION (for example us-east-1)
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- aws.bedrock.sentiment.model-id (optional override, default amazon.nova-pro-v1:0)
- aws.bedrock.voice.model-id (optional override, default mistral.voxtral-small-24b-2507)

To enable call recording (optional, off by default):
- CARECONNECT_RECORDING_ENABLED=true

Notes:
- In ECS Fargate, use task role/IAM instead of static AWS keys.
- Chime and Bedrock permissions must exist on the role.

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

Recording is OFF by default. To enable locally:

1. Set CARECONNECT_RECORDING_ENABLED=true in your env or application-dev.properties.

2. Add the following IAM permissions to your AWS dev user:

   iam:CreateServiceLinkedRole
     Resource: arn:aws:iam::*:role/aws-service-role/mediapipelines.chime.amazonaws.com/*

   s3:CreateBucket, s3:PutBucketPolicy, s3:PutObject, s3:GetObject, s3:ListBucket, s3:DeleteObject
     Resource: arn:aws:s3:::careconnect-recordings-*  (and :::careconnect-recordings-*/* for object actions)

   chime:CreateMediaCapturePipeline, chime:DeleteMediaCapturePipeline, chime:GetMediaCapturePipeline
     Resource: *

3. Everything else is automatic:
   - The S3 bucket (careconnect-recordings-{accountId}-{region}) is created at startup if absent.
   - The Chime bucket policy is applied at startup on every run (idempotent).
   - The IAM service-linked role AWSServiceRoleForAmazonChimeSDKMediaPipelines is created at
     startup if absent, provided iam:CreateServiceLinkedRole is in your policy.

   IF iam:CreateServiceLinkedRole cannot be added to your user policy, run this once manually
   (any team member, any machine — one-time per AWS account):

     aws iam create-service-linked-role --aws-service-name mediapipelines.chime.amazonaws.com

4. To clean up test recordings after a session, tap "Delete Call History (Dev)" in the patient
   details screen. This wipes all S3 objects under the recordings/ prefix AND all DB records.

## 8) Fast troubleshooting

If call screen opens but fails immediately:
- Verify you are logged in (JWT exists in app storage).
- Verify backend is running on localhost:8080.
- Verify AWS credentials/role and region.

If sentiment calls fail:
- Check backend logs for Bedrock invoke errors.
- Validate IAM permission bedrock:InvokeModel.

If Chime join fails:
- Check backend logs for chime:* permissions and region mismatch.

If recording fails with "service-linked role" error:
- Add iam:CreateServiceLinkedRole to your IAM user policy (see section 7 above), or
- Run: aws iam create-service-linked-role --aws-service-name mediapipelines.chime.amazonaws.com
- Restart the backend — it provisions the role at startup automatically.

If recording fails with "bucket policy does not exist":
- This should never happen after the startup provisioning was added.
- If it does, restart the backend — policy is re-applied on every start.

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
