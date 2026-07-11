<a id="top"></a>

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
[frontend/README.md](../frontend/README.md) (manual zip deploy) ·
[§11 — Fix Amplify “backend unhealthy” after redeploy](#11-fix-amplify-backend-unhealthy-after-redeploy)

---

## Table of contents

- [Architecture (short)](#architecture-short)
- [1. Prerequisites](#1-prerequisites)
- [2. First-time backend deploy](#2-first-time-backend-deploy)
- [3. What to redeploy when something changes](#3-what-to-redeploy-when-something-changes)
- [4. Rebuild and push the Docker image](#4-rebuild-and-push-the-docker-image)
- [5. Deploy the frontend (Amplify)](#5-deploy-the-frontend-amplify)
- [6. Amplify environment variables](#6-amplify-environment-variables)
- [7. Point the backend at your Amplify URL](#7-point-the-backend-at-your-amplify-url)
- [8. Smoke test](#8-smoke-test)
- [9. Share with testers](#9-share-with-testers)
- [10. Teardown](#10-teardown)
- [Troubleshooting (common)](#troubleshooting-common)
- [URL cheat sheet](#url-cheat-sheet)
- [11. Fix: Amplify “backend unhealthy” after redeploy](#11-fix-amplify-backend-unhealthy-after-redeploy)

---

## Architecture (short)

```text
Browser → Amplify (Flutter web) → API Gateway → VPC Link → ECS → RDS
```

Stack templates: [01-networking](./templates/01-networking.yaml) →
[02-data](./templates/02-data.yaml) →
[03-platform](./templates/03-platform.yaml) →
[04-service](./templates/04-service.yaml)

[TOP](#top)

---

## 1. Prerequisites

| Tool | Check |
| ---- | ----- |
| AWS CLI v2 | `aws --version` |
| Java 17 | `java -version` |
| Docker Desktop | Running (`docker --version`) |
| Flutter (frontend only) | `flutter --version` |

### AWS deploy user (every session)

The profile name **`careconnect-sso`** is only a local CLI label — not school SSO.
Configure it once with **IAM access keys** from your instructor / account owner:

```powershell
aws configure --profile careconnect-sso
# Region: us-east-1
```

Before each deploy session, verify the profile:

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
aws sts get-caller-identity --profile careconnect-sso
```

```bash
export AWS_PROFILE="careconnect-sso"
aws sts get-caller-identity --profile careconnect-sso
```

Expected: `"Arn": "arn:aws:iam::<account>:user/<your-username>"` (not `...:root`).

[TOP](#top)

---

## 2. First-time backend deploy

Use this only when **no CareConnect stacks exist** for your environment, or you are
creating a **new** `ENVIRONMENT` name. **Expect ~15–30 minutes** (RDS is slow).

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

This check confirms the API is up. It does **not** prove browser/CORS access from
Amplify — that requires [§7](#7-point-the-backend-at-your-amplify-url) and the
[§8](#8-smoke-test) `Origin` header test after the frontend is deployed.

### First-time path: backend, then Amplify (recommended order)

When you want a shareable hosted app, run these in order (URLs are **not**
hardcoded in source — they come from stack outputs and Amplify env vars):

1. [§2](#2-first-time-backend-deploy) — backend stacks (this section)
2. [§5](#5-deploy-the-frontend-amplify) — deploy Flutter web to Amplify
3. [§6](#6-amplify-environment-variables) — set `BACKEND_URL`, `APP_DOMAIN`, `APP_PORT`
4. [§7](#7-point-the-backend-at-your-amplify-url) — **required:** allow your Amplify
   origin in `CorsAllowedList` (browser health check fails without this)
5. [§8](#8-smoke-test) — verify health **with** `-H "Origin: $FRONTEND_URL"`

If the welcome page later says “backend unhealthy” but `curl` health works, see
[§11](#11-fix-amplify-backend-unhealthy-after-redeploy).

If stacks already exist and you only changed code or IAM, use
[§3 What to redeploy](#3-what-to-redeploy-when-something-changes) instead of a full deploy.

[TOP](#top)

---

## 3. What to redeploy when something changes

After the first deploy, pick the **smallest** path that matches your diff. Replace
`cfdemo` with your `ENVIRONMENT` if different.

| What you changed | Redeploy path | Typical time |
| ---------------- | ------------- | ------------ |
| **Java / Kotlin** (`backend/core/src/...`) | [§4 Docker image](#4-rebuild-and-push-the-docker-image) — **Option A** (`cdeploy_app_only`). **After app-only:** re-apply [§7](#7-point-the-backend-at-your-amplify-url) if Amplify shows “backend unhealthy” ([§11](#11-fix-amplify-backend-unhealthy-after-redeploy)). | ~5–15 min |
| **`application-dev.properties`** (CORS, `frontend.base-url`) | [§4](#4-rebuild-and-push-the-docker-image) **and/or** [§7](#7-point-the-backend-at-your-amplify-url) if only stack env overrides | varies |
| **`03-platform.yaml`** (ECS task role IAM — Chime, Bedrock, S3, …) | Platform stack update + force ECS (below) | ~3–10 min |
| **`04-service.yaml`** params only (`CorsAllowedList`, `FrontendBaseUrl`, CPU/memory) | [§7](#7-point-the-backend-at-your-amplify-url) service stack deploy + force ECS | ~5–15 min |
| **Deploy scripts only** (`cdeploy_*.ps1`) | No AWS change until you **run** a deploy; use app-only to smoke-test | — |
| **Flutter** (`frontend/...`) | [§5](#5-deploy-the-frontend-amplify) Amplify rebuild or zip upload | ~5–10 min |
| **New Amplify URL** | [§6](#6-amplify-environment-variables) + [§7](#7-point-the-backend-at-your-amplify-url) + frontend rebuild if `BACKEND_URL` wrong in build | ~15 min |
| **Networking / RDS / ECR** (`01`–`03` templates, new env) | Full deploy [§2](#2-first-time-backend-deploy) or manual stack order in [README](./README.md) | 15–30+ min |

### Platform stack only (IAM / ECR / cluster changes)

When `03-platform.yaml` changes (for example ECS task role permissions for video
calls or Bedrock):

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
cd $APP_ROOT

aws cloudformation deploy `
  --stack-name careconnect-platform-cfdemo `
  --template-file "$APP_ROOT/cloudformation-fargate/templates/03-platform.yaml" `
  --parameter-overrides file://$APP_ROOT/cloudformation-fargate/parameters/cfdemo-platform.json `
  --capabilities CAPABILITY_NAMED_IAM `
  --no-fail-on-empty-changeset `
  --profile careconnect-sso `
  --region us-east-1

aws ecs update-service `
  --cluster careconnect-cfdemo-cluster `
  --service careconnect-cfdemo-backend `
  --force-new-deployment `
  --profile careconnect-sso `
  --region us-east-1
```

See [README — ECS task role permissions](./README.md#ecs-task-role-permissions) for
what the task role policy covers.

### App-only backend redeploy (code or image refresh)

When all four stacks already exist and you changed **backend code** or want a fresh
image (includes `docker build --platform linux/amd64` from the deploy scripts):

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
cd $APP_ROOT
.\cloudformation-fargate\cdeploy_app_only.ps1 -Environment cfdemo -Profile careconnect-sso
```

```bash
export AWS_PROFILE="careconnect-sso"
cd "$APP_ROOT"
./cloudformation-fargate/cdeploy_app_only.sh --environment cfdemo --profile careconnect-sso
```

Or trigger [backend-app-deploy.yml](../.github/workflows/backend-app-deploy.yml) from
GitHub Actions.

**Does not** update the platform stack — run the platform commands above if IAM changed.

**After every app-only redeploy (Amplify users):** The script updates the service
stack from `parameters/{env}-service.json`, which defaults `CorsAllowedList` to
localhost only. That can **wipe** your Amplify origin even when backend code did not
change.

1. Run [§7](#7-point-the-backend-at-your-amplify-url) with your `FRONTEND_URL` in
   `CorsAllowedList` and `FrontendBaseUrl` (or follow the full playbook in
   [§11](#11-fix-amplify-backend-unhealthy-after-redeploy)).
2. Run [§8](#8-smoke-test) — health check **with** `-H "Origin: $FRONTEND_URL"`.
3. Reload the Amplify welcome page.

You do **not** fix this by hardcoding URLs in Java or Dart. If only the API
Gateway URL changed, also update Amplify `BACKEND_URL` ([§6](#6-amplify-environment-variables))
and redeploy the frontend branch.

### Quick decision tree

```text
Stacks missing?     → §2 First-time full deploy
IAM in 03-platform? → Platform stack + force ECS
Java / properties?  → §4 Docker image (app-only or manual)
CORS / Amplify URL? → §7 Service stack (+ §6 frontend env if needed)
Amplify unhealthy, curl OK? → §11
Flutter UI only?    → §5 Amplify
```

[TOP](#top)

---

## 4. Rebuild and push the Docker image

ECS runs a **Docker image** from ECR. Rebuild when backend source or
`application-*.properties` changes, or when you need a fresh `linux/amd64` image on
Apple Silicon / ARM Windows.

**Prerequisites:** Docker Desktop running, `$Env:AWS_PROFILE = "careconnect-sso"`,
platform stack `careconnect-platform-{env}` already exists.

### Option A — App-only script (recommended)

Builds the JAR, builds the image (`--platform linux/amd64`), pushes to ECR, and
updates the **service** stack with the new `BackendImageUri`:

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
cd $APP_ROOT
.\cloudformation-fargate\cdeploy_app_only.ps1 -Environment cfdemo -Profile careconnect-sso
```

```bash
export AWS_PROFILE="careconnect-sso"
cd "$APP_ROOT"
./cloudformation-fargate/cdeploy_app_only.sh --environment cfdemo --profile careconnect-sso
```

On success, retry the [health check](#8-smoke-test).

**CORS warning:** `cdeploy_app_only` deploys the service stack using
`parameters/{env}-service.json`, which defaults `CorsAllowedList` to localhost only.
That can **reset** a previously configured Amplify origin. After every app-only
deploy, run [§7](#7-point-the-backend-at-your-amplify-url) (or [§11](#11-fix-amplify-backend-unhealthy-after-redeploy))
with your `FRONTEND_URL` — you do **not** hardcode URLs in Java or Dart source.

### Option B — Manual build and push

Use when you need full control (custom tag, debugging a failed script step).

**4a. Build the JAR** (from `backend/core`, not repo root):

```powershell
cd "$APP_ROOT\backend\core"
.\mvnw.cmd -B -ntp clean package -Pdocker -DskipTests
```

```bash
cd "$APP_ROOT/backend/core"
./mvnw -B -ntp clean package -Pdocker -DskipTests
```

Confirm `target/careconnect-backend-0.0.1-SNAPSHOT.jar` exists.

**4b. Verify CORS placeholders** (if you changed `application-dev.properties`):

```powershell
Select-String -Path "$APP_ROOT\backend\core\target\classes\application-dev.properties" `
  -Pattern "cors_allowed|frontend.base-url"
```

You want `${CORS_ALLOWED_LIST` and `${APP_FRONTEND_BASE_URL` in the output. If you
see only `localhost`, run `clean package` again.

**4c. Log in to ECR, build, tag, and push:**

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
$Region = "us-east-1"
$ImageTag = "cfdemo-$(Get-Date -Format 'yyyyMMddHHmmss')"

$RepositoryUri = aws cloudformation describe-stacks `
  --profile careconnect-sso --region $Region `
  --stack-name careconnect-platform-cfdemo `
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" `
  --output text

$RegistryHost = ($RepositoryUri -split "/", 2)[0]
$ImageUri = "${RepositoryUri}:${ImageTag}"

aws ecr get-login-password --profile careconnect-sso --region $Region |
  docker login --username AWS --password-stdin $RegistryHost

cd "$APP_ROOT\backend\core"
docker build --platform linux/amd64 -t "careconnect-backend-local:$ImageTag" .
docker tag "careconnect-backend-local:$ImageTag" $ImageUri
docker push $ImageUri

Write-Host "Pushed: $ImageUri"
```

```bash
export AWS_PROFILE="careconnect-sso"
REGION="us-east-1"
IMAGE_TAG="cfdemo-$(date +%Y%m%d%H%M%S)"

REPOSITORY_URI="$(aws cloudformation describe-stacks \
  --profile careconnect-sso --region "$REGION" \
  --stack-name careconnect-platform-cfdemo \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" \
  --output text)"

REGISTRY_HOST="${REPOSITORY_URI%%/*}"
IMAGE_URI="${REPOSITORY_URI}:${IMAGE_TAG}"

aws ecr get-login-password --profile careconnect-sso --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY_HOST"

cd "$APP_ROOT/backend/core"
docker build --platform linux/amd64 -t "careconnect-backend-local:${IMAGE_TAG}" .
docker tag "careconnect-backend-local:${IMAGE_TAG}" "$IMAGE_URI"
docker push "$IMAGE_URI"

echo "Pushed: $IMAGE_URI"
```

**4d. Point the service stack at the new image** and roll ECS:

```powershell
aws cloudformation deploy `
  --profile careconnect-sso --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --template-file "$APP_ROOT/cloudformation-fargate/templates/04-service.yaml" `
  --capabilities CAPABILITY_NAMED_IAM `
  --no-fail-on-empty-changeset `
  --parameter-overrides `
    Environment=cfdemo BackendImageUri=$ImageUri SpringProfile=dev `
    FrontendBaseUrl=$FRONTEND_URL `
    "CorsAllowedList=http://localhost:*,http://127.0.0.1:*,$FRONTEND_URL" `
    ContainerPort=8081 DesiredCount=1 TaskCpu=1024 TaskMemory=3072 `
    HealthCheckPath=/v1/api/test/health DomainName= HostedZoneId=

aws ecs update-service --profile careconnect-sso --region us-east-1 `
  --cluster careconnect-cfdemo-cluster --service careconnect-cfdemo-backend `
  --force-new-deployment
```

Set `$FRONTEND_URL` before step 4d, or reuse the existing `BackendImageUri` from the
stack if you are only refreshing the image and CORS is already correct:

```powershell
# Reuse current image URI from stack (skip 4c) when only rolling tasks:
$ImageUri = aws cloudformation describe-stacks `
  --profile careconnect-sso --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --query "Stacks[0].Parameters[?ParameterKey=='BackendImageUri'].ParameterValue" `
  --output text
```

Wait 2–5 minutes, then run [§8 Smoke test](#8-smoke-test).

[TOP](#top)

---

## 5. Deploy the frontend (Amplify)

You need `BACKEND_URL` from the backend deploy before the hosted app can call the API.

### Option A — Git-connected

1. AWS Console → **Amplify** → **Create new app** → **Host web app** → connect this repo.
2. Set **app root** to `frontend`.
3. Amplify picks up [frontend/amplify.yml](../frontend/amplify.yml).
4. Add environment variables ([§6](#6-amplify-environment-variables)), then deploy.

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

**Next (required for browser access):** Run [§7](#7-point-the-backend-at-your-amplify-url)
so the backend allows your Amplify origin in CORS, then [§8](#8-smoke-test). Without
§7, `curl` health from your PC can succeed while the welcome page reports the backend
as unhealthy ([§11](#11-fix-amplify-backend-unhealthy-after-redeploy)).

[TOP](#top)

---

## 6. Amplify environment variables

Amplify console → your app → branch → **Environment variables**:

| Variable | Value |
| -------- | ----- |
| `BACKEND_URL` | API Gateway URL from backend deploy |
| `APP_DOMAIN` | `FRONTEND_HOST` (hostname only, no `https://`) |
| `APP_PORT` | `443` |

Redeploy the branch after saving. These are passed into the Flutter build by
[amplify.yml](../frontend/amplify.yml).

**Not hardcoded in source:** `BACKEND_URL` is a **build-time** variable (Amplify
env var or `--dart-define`). Read the current API URL from the stack when needed:

```powershell
$BACKEND_URL = aws cloudformation describe-stacks `
  --profile careconnect-sso --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" `
  --output text
```

If `BACKEND_URL` is missing at Amplify build time, the Flutter web app falls back
to `http://localhost:8080` and the welcome page reports the backend as unhealthy.

[TOP](#top)

---

## 7. Point the backend at your Amplify URL

**When to run this:** After the first Amplify deploy ([§5](#5-deploy-the-frontend-amplify)),
and again after **every** [app-only redeploy](#app-only-backend-redeploy-code-or-image-refresh)
if the welcome page shows “backend unhealthy” ([§11](#11-fix-amplify-backend-unhealthy-after-redeploy)).

The browser sends `Origin: FRONTEND_URL`. Update the **service stack** so ECS
passes your Amplify URL into the Spring app ([04-service.yaml](./templates/04-service.yaml)).
No hardcoded URLs in backend source — only CloudFormation parameters:

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

For a **new Docker image** plus CORS in one flow, see [§4](#4-rebuild-and-push-the-docker-image).
If Step 1B in [§11](#11-fix-amplify-backend-unhealthy-after-redeploy) still fails after
this deploy, see [§11 — troubleshooting](#11-fix-amplify-backend-unhealthy-after-redeploy).

[TOP](#top)

---

## 8. Smoke test

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

If plain `curl` works but the `Origin` test or welcome page fails, see
[§11](#11-fix-amplify-backend-unhealthy-after-redeploy).

[TOP](#top)

---

## 9. Share with testers

| What | URL |
| ---- | --- |
| Frontend (E2E entry) | `FRONTEND_URL` |
| Backend API | `BACKEND_URL` |
| Health | `$BACKEND_URL/v1/api/test/health` |

Testers only need the **frontend** URL in a browser — not AWS credentials.

[TOP](#top)

---

## 10. Teardown

When finished with the sandbox:

```powershell
.\cloudformation-fargate\cdestroy_cloudformation.ps1 -Environment cfdemo -Profile careconnect-sso
```

```bash
./cloudformation-fargate/cdestroy_cloudformation.sh --environment cfdemo --profile careconnect-sso
```

See [README — Teardown](./README.md#teardown-cfdemo) for ECR cleanup if a stack
delete fails.

[TOP](#top)

---

## Troubleshooting (common)

| Symptom | Fix |
| ------- | --- |
| `Unable to locate credentials` | `$Env:AWS_PROFILE = "careconnect-sso"`; run `aws configure --profile careconnect-sso` |
| `get-caller-identity` shows `...:root` | Reconfigure profile with **IAM user** access keys, not root |
| `No host specified in URI` | `BACKEND_URL` must include `https://` |
| Welcome page: backend unhealthy (but `curl` health OK) | Almost always **CORS** or wrong baked-in `BACKEND_URL` — see [§11](#11-fix-amplify-backend-unhealthy-after-redeploy) |
| `Invalid CORS request` with `Origin` header | [§7](#7-point-the-backend-at-your-amplify-url): `CorsAllowedList` must include exact `FRONTEND_URL` |
| Login redirects to localhost | [§7](#7-point-the-backend-at-your-amplify-url): `FrontendBaseUrl` + correct `APP_DOMAIN` in Flutter build |
| 502 from API Gateway | ECS tasks still starting — wait and retry health check |
| `ClusterNotFoundException` on ECS update | Use `careconnect-cfdemo-cluster` (includes `-cluster`) |
| Deploy script not found | Run from `APP_ROOT` (folder containing `cloudformation-fargate/`) |
| `docker build`: Dockerfile not found | Run from `APP_ROOT/backend/core` |
| Docker build fails on ARM Mac/PC | Use `--platform linux/amd64` ([§4](#4-rebuild-and-push-the-docker-image)) |

More: [README — Common Failure Modes](./README.md#common-failure-modes).

[TOP](#top)

---

## URL cheat sheet

| Value | Goes in |
| ----- | ------- |
| `BACKEND_URL` | Amplify env `BACKEND_URL`, Flutter `--dart-define=BACKEND_URL` |
| `FRONTEND_HOST` | Amplify env `APP_DOMAIN`, Flutter `--dart-define=APP_DOMAIN` |
| `FRONTEND_URL` | Stack `FrontendBaseUrl`, entry in `CorsAllowedList` |

Do **not** put `FRONTEND_URL` in the Docker image or committed parameter files
unless your team intentionally checks in non-secret deploy config.

[TOP](#top)

---

## 11. Fix: Amplify “backend unhealthy” after redeploy

Use this when:

- `curl` / `Invoke-RestMethod` against `$BACKEND_URL/v1/api/test/health` returns
  healthy JSON from your PC, **but**
- The **Amplify welcome page** warns that the backend is unhealthy.

That pattern means the API is up; the **browser** request failed. This is almost
never fixed by changing backend Java code or hardcoding URLs in the repo.

### Why `curl` works but the browser does not

| Check | Sends `Origin` header? | What it tests |
| ----- | ---------------------- | ------------- |
| `curl` from your laptop | No | API Gateway + ECS are up |
| Amplify welcome page (`GET …/v1/api/test/health`) | Yes (`https://<amplify-host>`) | **Spring CORS** on ECS must allow your Amplify origin |

Opening the health URL in a browser **tab** also omits a cross-origin `Origin`
header, so it can look healthy while the hosted app still fails.

### Two configuration surfaces (neither is hardcoded in source)

| Direction | What | Where to set it |
| --------- | ---- | --------------- |
| Frontend → API | `BACKEND_URL` | Amplify branch **Environment variables** → baked at build via [amplify.yml](../frontend/amplify.yml) |
| API → browser | `FRONTEND_URL` in `CorsAllowedList` | CloudFormation service stack **`04-service.yaml`** parameters → ECS `CORS_ALLOWED_LIST` → `careconnect.cors_allowed` in `application-dev.properties` |

Backend CORS is **not** configured by editing Java for each deploy. Update the
**service stack parameters** ([§7](#7-point-the-backend-at-your-amplify-url)).

### Step 1 — Diagnose (30 seconds)

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
$BACKEND_URL = aws cloudformation describe-stacks `
  --profile careconnect-sso --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" `
  --output text
$FRONTEND_URL = "https://<your-amplify-host>.amplifyapp.com"   # your real Amplify URL

# A — plain health (should pass)
curl.exe -s "$BACKEND_URL/v1/api/test/health"

# B — simulates Amplify browser (this is the real test)
curl.exe -s "$BACKEND_URL/v1/api/test/health" -H "Origin: $FRONTEND_URL"
```

- **A OK, B fails** (`Invalid CORS request` or non-JSON) → fix CORS ([Step 2](#step-2--fix-cors-service-stack-no-source-hardcoding)).
- **Both OK** but welcome page still warns → fix frontend `BACKEND_URL` ([Step 3](#step-3--fix-frontend-backend_url-amplify-env-not-source-code)).
- On Amplify: **F12 → Network** → failed request to `/v1/api/test/health` shows CORS or wrong host.

### Step 2 — Fix CORS (service stack, no source hardcoding)

Common after **`cdeploy_app_only`**: the script updates the service stack from
`parameters/cfdemo-service.json`, whose default `CorsAllowedList` is localhost-only.
That **overwrites** a previously working Amplify origin.

Re-apply your Amplify URL via stack parameters (same as [§7](#7-point-the-backend-at-your-amplify-url)):

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
$FRONTEND_URL = "https://<your-amplify-host>.amplifyapp.com"

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
    Environment=cfdemo BackendImageUri=$ImageUri SpringProfile=dev `
    FrontendBaseUrl=$FRONTEND_URL `
    "CorsAllowedList=http://localhost:*,http://127.0.0.1:*,$FRONTEND_URL" `
    ContainerPort=8081 DesiredCount=1 TaskCpu=1024 TaskMemory=3072 `
    HealthCheckPath=/v1/api/test/health DomainName= HostedZoneId=
```

That usually good if it says "up to date." Just parameters need to be changed. But if not, you can also run this:

```powershell
aws ecs update-service --profile careconnect-sso --region us-east-1 `
  --cluster careconnect-cfdemo-cluster --service careconnect-cfdemo-backend `
  --force-new-deployment
```


Wait 2–5 minutes, then repeat **Step 1B**. Expect healthy JSON, not
`Invalid CORS request`.

**Optional (local only):** add your Amplify URL to
`parameters/cfdemo-service.json` `CorsAllowedList` / `FrontendBaseUrl` before
app-only deploy so the script does not reset CORS — do not commit team-specific
URLs unless your process allows it.

### Step 3 — Fix frontend `BACKEND_URL` (Amplify env, not source code)

Amplify console → your app → branch → **Environment variables**:

| Variable | Value |
| -------- | ----- |
| `BACKEND_URL` | `$BACKEND_URL` from stack `ApiEndpoint` (no trailing slash, no `/v1`) |
| `APP_DOMAIN` | Amplify hostname only |
| `APP_PORT` | `443` |

**Redeploy the Amplify branch** after saving — `BACKEND_URL` is compiled into the
web build; changing the variable alone does not update an already-deployed bundle.

### After every backend redeploy (checklist)

1. `curl` health from PC ([§8](#8-smoke-test)).
2. `curl` health **with `-H "Origin: $FRONTEND_URL"`** ([Step 1B](#step-1--diagnose-30-seconds)).
3. If Step 2 failed → [Step 2](#step-2--fix-cors-service-stack-no-source-hardcoding).
4. Open Amplify welcome page — no unhealthy warning.
5. If API Gateway URL changed → update Amplify `BACKEND_URL` and redeploy frontend.

More CORS detail: [README — CORS smoke test](./README.md#12a-cors-smoke-test-deployed-environment) and
[README — Amplify unhealthy / CORS after redeploy](./README.md#7-amplify-welcome-page-backend-unhealthy-cors-after-redeploy).

[TOP](#top)
