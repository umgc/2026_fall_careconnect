# CareConnect Local Development Programmer Guide

This guide captures the **current known-good setup** used in team troubleshooting, including:
- standard local run with backend/frontend,
- test-call verification,
- adding patients to a caregiver profile,
- and a **no-AWS-account mode** for local development.

## Path Placeholders

Use these placeholders throughout this document:

- `{{REPO_ROOT}}` = your local repo root (example: `D:\dev\2026_spring_careconnect`)
- `{{BACKEND_DIR}}` = `{{REPO_ROOT}}\backend\core`
- `{{FRONTEND_DIR}}` = `{{REPO_ROOT}}\frontend`

---

## 1) Prerequisites

- Windows + PowerShell
- Docker Desktop running
- Java/JDK compatible with project
- Flutter SDK + Chrome
- Repo checked out at:
  - `{{REPO_ROOT}}`

---

## 2) Database (Postgres) Start

Use the local container on port `5433`.

```powershell
Set-Location {{REPO_ROOT}}
if (docker ps -a --format "{{.Names}}" | Select-String -Pattern "^cc_pg_5433$" -Quiet) {
  docker start cc_pg_5433 | Out-Null
} else {
  docker run -d --name cc_pg_5433 `
    -e POSTGRES_USER=postgres `
    -e POSTGRES_PASSWORD=careconnect123 `
    -e POSTGRES_DB=careconnect `
    -p 5433:5432 pgvector/pgvector:pg15 | Out-Null
}

docker exec cc_pg_5433 psql -U postgres -d careconnect -c "ALTER USER postgres WITH PASSWORD 'careconnect123';"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### pgvector requirement (Tasks 1.5 / 1.6)

The local container image `pgvector/pgvector:pg15` is **required** for Ask AI schema patches
(`SchemaPatchRunner`: pgvector extension + `retrieval_index_chunk` table).

**Production:** RDS/Aurora must have the `vector` extension enabled; patches run via
`SchemaPatchRunner` at ECS startup (not Flyway).

---

## 3) Backend Start (Two Modes)

Set location first:

```powershell
Set-Location {{BACKEND_DIR}}
```

### Mode A — Real AWS-backed calls (requires valid AWS creds)

Use this if you want real Chime behavior.

```powershell
$env:SERVER_PORT='8081'
$env:SPRING_PROFILES_ACTIVE='dev'
$env:JDBC_URI='jdbc:postgresql://localhost:5433/careconnect'
$env:DB_USER='postgres'
$env:DB_PASSWORD='careconnect123'
$env:CARECONNECT_AWS_ENABLED='true'
$env:AWS_DEFAULT_REGION='us-east-1'
$env:AWS_ACCESS_KEY_ID='...'
$env:AWS_SECRET_ACCESS_KEY='...'
# Optional for temporary credentials:
# $env:AWS_SESSION_TOKEN='...'

$env:CARECONNECT_OPENROUTER_ENABLED='true'
$env:DEEPSEEK_OPENROUTER_API_KEY='sk-local-mock-openrouter-key-1234567890'
$env:CARECONNECT_AI_ENABLED='false'

aws sts get-caller-identity
.\mvnw.cmd spring-boot:run
```

### Mode B — No AWS account (local-only, AWS ties disabled)

Use this to run locally without AWS credentials.

```powershell
$env:SERVER_PORT='8081'
$env:SPRING_PROFILES_ACTIVE='dev'
$env:JDBC_URI='jdbc:postgresql://localhost:5433/careconnect'
$env:DB_USER='postgres'
$env:DB_PASSWORD='careconnect123'
$env:CARECONNECT_AWS_ENABLED='false'

Remove-Item Env:AWS_ACCESS_KEY_ID,Env:AWS_SECRET_ACCESS_KEY,Env:AWS_SESSION_TOKEN,Env:AWS_PROFILE -ErrorAction SilentlyContinue

$env:CARECONNECT_OPENROUTER_ENABLED='true'
$env:DEEPSEEK_OPENROUTER_API_KEY='sk-local-mock-openrouter-key-1234567890'
$env:CARECONNECT_AI_ENABLED='false'

.\mvnw.cmd spring-boot:run
```

In Mode B, call join/end APIs are backed by a local mock meeting flow (no AWS Chime calls), so your functional call signaling tests still pass without cloud credentials.

### Backend quick health check

```powershell
Invoke-WebRequest -Uri 'http://localhost:8081/v1/api/auth/login' -Method Post -ContentType 'application/json' -Body '{"email":"x","password":"x"}' -UseBasicParsing
```

Expected: `401` means backend is up.

---

## 4) Frontend Start

```powershell
Set-Location {{FRONTEND_DIR}}
flutter pub get
flutter run -d chrome --web-port=50030 --dart-define=BACKEND_URL=http://localhost:8081
```

`--web-port=50030` matches the `APP_PORT` default used by the OAuth callback redirect URI. Omitting it will cause Google OAuth to fail on the wrong port.

For production-aligned web media testing, host a Chime SDK file on the same origin
and pass it explicitly:

```powershell
Set-Location {{FRONTEND_DIR}}
.\prepare-chime-sdk.ps1

flutter run -d chrome `
  --dart-define=BACKEND_URL=http://localhost:8081 `
  --dart-define=CHIME_SDK_URL=/amazon-chime-sdk.min.js `
  --dart-define=CHIME_SDK_ALLOW_EXTERNAL_FALLBACK=false
```

This keeps media initialization deterministic and avoids runtime CDN dependency.

`frontend/.chime_bundle/` is intentionally excluded from git because it contains
generated package artifacts and dependencies. The committed workflow uses
`frontend/prepare-chime-sdk.ps1` (or `frontend/prepare-chime-sdk.sh`) to generate
`frontend/web/amazon-chime-sdk.min.js` locally when needed.

If UI seems stale, do hard refresh in browser: `Ctrl+Shift+R`.

---

## 5) End-to-End Call Verification (API)

Run the built-in script:

```powershell
Set-Location {{REPO_ROOT}}
.\scripts\verify-two-user-call.ps1 -BaseUrl 'http://localhost:8081' -EndCall
```

Expected success:
- `caregiver_login=200`
- `patient_login=200`
- `caregiver_join_status=200`
- `patient_join_status=200`
- `end_call_status=200`
- `result=PASS`

---

## 6) In-App Test Flow

1. Open app as caregiver in one browser profile.
2. Open app as patient in a separate profile/incognito.
3. Caregiver starts call from patient details.
4. Patient receives incoming call notification popup.
5. Join on both sides.

> Current known status: signaling + join works; video/audio rendering may still show placeholder UI until media rendering implementation is completed.

---

## 7) Add Patient to Caregiver Profile (Supported API)

### 7.1 Login as caregiver

```powershell
$base='http://localhost:8081'
$body=@{ email='caregiver@careconnect.com'; password='password'; role='CAREGIVER' } | ConvertTo-Json
$login=Invoke-WebRequest -Method Post -Uri "$base/v1/api/auth/login" -ContentType 'application/json' -Body $body -UseBasicParsing
$token=($login.Content | ConvertFrom-Json).token
```

### 7.2 Create link (caregiver userId=2, patient userId=1 example)

```powershell
$linkBody=@{
  targetUserId=1
  linkType='PERMANENT'
  expiresAt=$null
  notes='manual link'
} | ConvertTo-Json

Invoke-WebRequest -Method Post `
  -Uri "$base/v1/api/caregiver-patient-links/caregivers/2/patients" `
  -Headers @{ Authorization="Bearer $token" } `
  -ContentType 'application/json' `
  -Body $linkBody -UseBasicParsing
```

### 7.3 Verify patient list

```powershell
Invoke-WebRequest -Method Get -Uri "$base/v1/api/caregiver-patient-links/caregivers/2/patients" -Headers @{Authorization="Bearer $token"} -UseBasicParsing
```

---

## 8) If Patient Disappears from Caregiver List

Most common root cause: link row exists but `status` is null/empty (API only returns `ACTIVE`).

Fix quickly:

```powershell
docker exec -e PGPASSWORD=careconnect123 cc_pg_5433 psql -U postgres -d careconnect -c "
UPDATE caregiver_patient_link
SET status='ACTIVE',
    link_type=COALESCE(link_type,'PERMANENT'),
    updated_at=NOW(),
    created_at=COALESCE(created_at,NOW())
WHERE caregiver_user_id=2 AND patient_user_id=1;
"
```

---

## 9) Common Troubleshooting

- `password authentication failed for user postgres`
  - Reset DB user password in container to `careconnect123` and restart backend.

- Backend boots but call join returns Chime `403 invalid security token`
  - AWS creds invalid or missing in the same terminal session used to start backend.
  - Re-run `aws sts get-caller-identity` in that terminal before startup.

- Frontend can log in but patient gets no call popup
  - Ensure both users are logged in simultaneously in separate browser contexts.
  - Hard-refresh both tabs.

- Frontend still points to wrong backend port
  - Always run with `--dart-define=BACKEND_URL=http://localhost:8081`.

- Flutter startup prints package/font warnings
  - Warnings like `flutter pub outdated` or missing Noto fallback fonts are typically non-blocking for local run and do not prevent backend/API call verification.

- `flutter build web` fails with `Avoid non-constant invocations of IconData`
  - Add `--no-tree-shake-icons` to the build command: `flutter build web --no-tree-shake-icons ...`
  - This is not needed for `flutter run` (debug builds skip tree-shaking).

---

## 10) Team Hand-off Notes

- Keep local DB container name/port consistent (`cc_pg_5433` on `5433`) to reduce setup drift.
- Use API link creation flow (Section 7) instead of ad hoc DB edits whenever possible.
- For no-AWS local work, run Mode B and avoid relying on external cloud credentials.
