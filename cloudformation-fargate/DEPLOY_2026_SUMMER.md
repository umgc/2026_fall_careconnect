# CareConnect — Summer 2026 deploy (backend + Amplify frontend)

Deploy the **backend** (API Gateway → VPC Link → ECS Fargate → RDS) and publish the
**Flutter web** app to **AWS Amplify** for a shareable HTTPS URL.

Paths below use **`APP_ROOT`** = your local clone of this repository (the folder
that contains `cloudformation-fargate/` and `backend/`).

| Placeholder | Example | Used for |
| ----------- | ------- | -------- |
| `APP_ROOT` | `C:\repos\2026_summer_careconnect` | Local repo path |
| `ENVIRONMENT` | `cfdemo` | CloudFormation stack suffix (`careconnect-*-cfdemo`) |
| `AWS_PROFILE` | `careconnect-sso` | AWS CLI profile on your machine |
| `BACKEND_URL` | `https://abc123.execute-api.us-east-1.amazonaws.com` | API Gateway base URL — **no** trailing slash, **no** `/v1` |
| `FRONTEND_URL` | `https://main.d1a2b3c4.amplifyapp.com` | Full Amplify URL (with `https://`) |
| `FRONTEND_HOST` | `main.d1a2b3c4.amplifyapp.com` | Amplify hostname only (for `APP_DOMAIN`) |

**Billing:** A full backend deploy creates paid AWS resources (RDS, Fargate, API
Gateway). Tear down when finished — see [README — Teardown](./README.md#teardown-cfdemo).

**More detail:** [README](./README.md) (stack walkthrough, failure modes) ·
[parameters/README.md](./parameters/README.md) ·
[frontend/README.md](../frontend/README.md) (manual zip deploy)

---

## Architecture (short)

```text
Browser → Amplify (Flutter web) → API Gateway → VPC Link → ECS → RDS
```

Stack templates: [01-networking](./templates/01-networking.yaml) →
[02-data](./templates/02-data.yaml) →
[03-platform](./templates/03-platform.yaml) →
[04-service](./templates/04-service.yaml)

---

## 1. Prerequisites

| Tool | Check |
| ---- | ----- |
| AWS CLI v2 | `aws --version` |
| Java 17 | `java -version` |
| Docker Desktop | Running (`docker --version`) |
| Flutter (frontend only) | `flutter --version` |

Configure AWS CLI once (use credentials from your instructor / account owner):

```powershell
aws configure --profile careconnect-sso
# Region: us-east-1
```

```bash
aws configure --profile careconnect-sso
```

Before each session:

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
aws sts get-caller-identity --profile careconnect-sso
```

```bash
export AWS_PROFILE="careconnect-sso"
aws sts get-caller-identity --profile careconnect-sso
```

---

## 2. Deploy the backend

Pick an environment name (`cfdemo` is a good sandbox; see
[parameters/](./parameters/)). **First deploy takes ~15–30 minutes** (RDS is slow).

Set database secrets for this terminal session (do not commit these):

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
$env:CARECONNECT_DATABASE_MASTER_PASSWORD = "<strong-postgres-password>"
$env:CARECONNECT_JWT_SECRET = "<random-string-at-least-32-chars>"

cd $APP_ROOT
.\cloudformation-fargate\cdeploy_cloudformation.ps1 -Environment cfdemo -Profile careconnect-sso
```

```bash
export AWS_PROFILE="careconnect-sso"
export CARECONNECT_DATABASE_MASTER_PASSWORD="<strong-postgres-password>"
export CARECONNECT_JWT_SECRET="<random-string-at-least-32-chars>"

cd "$APP_ROOT"
./cloudformation-fargate/cdeploy_cloudformation.sh --environment cfdemo --profile careconnect-sso
```

On success the script prints **`API Endpoint`** and **`Health check`**. Save that
value as `BACKEND_URL`.

**Alternative:** GitHub Actions full deploy — see
[GITHUB_ACTIONS_SETUP.md](./GITHUB_ACTIONS_SETUP.md) and
[backend-full-deploy.yml](../.github/workflows/backend-full-deploy.yml).

**Verify:**

```powershell
Invoke-RestMethod "$BACKEND_URL/v1/api/test/health"
```

```bash
curl -sf "$BACKEND_URL/v1/api/test/health"
```

Expect JSON with a healthy status. Wait 2–5 minutes if the service stack just finished.

---

## 3. Deploy the frontend (Amplify)

You need `BACKEND_URL` from step 2 before the hosted app can call the API.

### Option A — Git-connected

1. AWS Console → **Amplify** → **Create new app** → **Host web app** → connect this repo.
2. Set **app root** to `frontend`.
3. Amplify picks up [frontend/amplify.yml](../frontend/amplify.yml).
4. Add environment variables (step 4 below), then deploy.

### Option B — Manual zip

See [frontend/README.md — AWS Amplify Front-End Deployment](../frontend/README.md#aws-amplify-front-end-deployment).

Build locally:

```powershell
cd "$APP_ROOT\frontend"
flutter build web --release --base-href "/" `
  --dart-define=BACKEND_URL=$BACKEND_URL `
  --dart-define=APP_DOMAIN=$FRONTEND_HOST `
  --dart-define=APP_PORT=443
```

```bash
cd "$APP_ROOT/frontend"
flutter build web --release --base-href "/" \
  --dart-define=BACKEND_URL="$BACKEND_URL" \
  --dart-define=APP_DOMAIN="$FRONTEND_HOST" \
  --dart-define=APP_PORT=443
```

Zip the **contents** of `frontend/build/web` (not the `web` folder itself) and
upload via Amplify **Deploy updates** → drag and drop.

After deploy, note the Amplify URL as `FRONTEND_URL` and the hostname as
`FRONTEND_HOST`.

---

## 4. Amplify environment variables

Amplify console → your app → branch → **Environment variables**:

| Variable | Value |
| -------- | ----- |
| `BACKEND_URL` | API Gateway URL from step 2 |
| `APP_DOMAIN` | `FRONTEND_HOST` (hostname only, no `https://`) |
| `APP_PORT` | `443` |

Redeploy the branch after saving. These are passed into the Flutter build by
[amplify.yml](../frontend/amplify.yml).

---

## 5. Point the backend at your Amplify URL

The browser sends `Origin: FRONTEND_URL`. Update the **service stack** so ECS
passes your Amplify URL into the Spring app ([04-service.yaml](./templates/04-service.yaml)):

| Stack parameter | Purpose |
| --------------- | ------- |
| `FrontendBaseUrl` | Auth redirects, email links (`APP_FRONTEND_BASE_URL`) |
| `CorsAllowedList` | Allowed browser origins (`CORS_ALLOWED_LIST`) |

Run after Amplify is live and you know `FRONTEND_URL`:

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
$ImageUri = aws cloudformation describe-stacks `
  --profile careconnect-sso --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --query "Stacks[0].Parameters[?ParameterKey=='BackendImageUri'].ParameterValue" `
  --output text

aws cloudformation deploy `
  --profile careconnect-sso --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --template-file "$APP_ROOT/cloudformation-fargate/templates/04-service.yaml" `
  --capabilities CAPABILITY_NAMED_IAM `
  --no-fail-on-empty-changeset `
  --parameter-overrides `
    Environment=cfdemo BackendImageUri=$ImageUri SpringProfile=prod `
    FrontendBaseUrl=$FRONTEND_URL `
    "CorsAllowedList=http://localhost:*,http://127.0.0.1:*,$FRONTEND_URL" `
    ContainerPort=8081 DesiredCount=1 TaskCpu=1024 TaskMemory=3072 `
    HealthCheckPath=/v1/api/test/health DomainName= HostedZoneId=

aws ecs update-service --profile careconnect-sso --region us-east-1 `
  --cluster careconnect-cfdemo-cluster --service careconnect-cfdemo-backend `
  --force-new-deployment
```

Replace `cfdemo` in stack/cluster names if you used a different `ENVIRONMENT`.

**Faster path next time (code only):** [cdeploy_app_only.ps1](./cdeploy_app_only.ps1)
/ [cdeploy_app_only.sh](./cdeploy_app_only.sh) — still update `CorsAllowedList` when
the Amplify URL changes.

---

## 6. Smoke test

Set `BACKEND_URL` and `FRONTEND_URL`, then follow
[README — CORS smoke test](./README.md#12a-cors-smoke-test-deployed-environment).

Quick check:

```powershell
curl.exe -s "$BACKEND_URL/v1/api/test/health" -H "Origin: $FRONTEND_URL"
```

```bash
curl -s "$BACKEND_URL/v1/api/test/health" -H "Origin: $FRONTEND_URL"
```

Expect healthy JSON, not `Invalid CORS request`. Open `FRONTEND_URL` in a browser;
the welcome page should not warn that the backend is unhealthy.

---

## 7. Share with testers

| What | URL |
| ---- | --- |
| Frontend (E2E entry) | `FRONTEND_URL` |
| Backend API | `BACKEND_URL` |
| Health | `$BACKEND_URL/v1/api/test/health` |

Testers only need the **frontend** URL in a browser — not AWS credentials.

---

## 8. Teardown

When finished with the sandbox:

```powershell
.\cloudformation-fargate\cdestroy_cloudformation.ps1 -Environment cfdemo -Profile careconnect-sso
```

```bash
./cloudformation-fargate/cdestroy_cloudformation.sh --environment cfdemo --profile careconnect-sso
```

See [README — Teardown](./README.md#teardown-cfdemo) for ECR cleanup if a stack
delete fails.

---

## Troubleshooting (common)

| Symptom | Fix |
| ------- | --- |
| `No host specified in URI` | `BACKEND_URL` must include `https://` |
| Welcome page: backend unhealthy | Wrong `BACKEND_URL` in Flutter build, or CORS — redo steps 4–6 |
| `Invalid CORS request` with `Origin` header | Step 5: `CorsAllowedList` must include exact `FRONTEND_URL` |
| Login redirects to localhost | Step 5: `FrontendBaseUrl` must be `FRONTEND_URL`; rebuild with correct `APP_DOMAIN` |
| 502 from API Gateway | ECS tasks still starting — wait and retry health check |
| Deploy script not found | Run from `APP_ROOT` (folder containing `cloudformation-fargate/`) |
| Docker build fails | Run from `APP_ROOT/backend/core`; use `-Pdocker` (deploy script does this) |

More: [README — Common Failure Modes](./README.md#common-failure-modes).

---

## URL cheat sheet

| Value | Goes in |
| ----- | ------- |
| `BACKEND_URL` | Amplify env `BACKEND_URL`, Flutter `--dart-define=BACKEND_URL` |
| `FRONTEND_HOST` | Amplify env `APP_DOMAIN`, Flutter `--dart-define=APP_DOMAIN` |
| `FRONTEND_URL` | Stack `FrontendBaseUrl`, entry in `CorsAllowedList` |

Do **not** put `FRONTEND_URL` in the Docker image or committed parameter files
unless your team intentionally checks in non-secret deploy config.
