## CareConnect Fargate CloudFormation

This directory contains a clean CloudFormation stack set for the CareConnect
backend running on:

- Amazon ECS Fargate
- Application Load Balancer
- Amazon RDS PostgreSQL
- Amazon ECR

It does not depend on the older `cloudformation/` or `terraform_aws/` layouts.

This stack set was validated by deploying a parallel `cfdemo` environment in
the same AWS account without interfering with the existing manually created
Fargate deployment.

### Table of Contents

- [Stack order](#stack-order)
- [One-Command Scripts](#one-command-scripts)
- [GitHub Actions Backend Deploy](#github-actions-backend-deploy)
- [GitHub Actions Full Deploy](#github-actions-full-deploy)
- [What each stack owns](#what-each-stack-owns)
- [Design choices](#design-choices)
- [Required application contract](#required-application-contract)
- [Parameter files](#parameter-files)
- [Example deploy commands](#example-deploy-commands)
- [macOS / Linux translation](#macos--linux-translation)
- [Parallel environment pattern](#parallel-environment-pattern)
- [Student Walkthrough:](#student-walkthrough-cfdemo) `cfdemo`
- [Teardown:](#teardown-cfdemo) `cfdemo`
- [Important safety note](#important-safety-note)
- [macOS / Linux teardown translation](#macos--linux-teardown-translation)
- [Common Failure Modes](#common-failure-modes)



### Stack order

1. `01-networking.yaml`
2. `02-data.yaml`
3. `03-platform.yaml`
4. Build and push the backend image to ECR
5. `04-service.yaml`



### One-Command Scripts

If you want the fastest path, use the deployment and teardown scripts instead of
running each AWS CLI command manually.

#### Windows / PowerShell

Deploy:

```powershell
.\cloudformation-fargate\cdeploy_cloudformation.ps1 -Environment cfdemo -Profile careconnect-sso
```

Teardown:

```powershell
.\cloudformation-fargate\cdestroy_cloudformation.ps1 -Environment cfdemo -Profile careconnect-sso
```



#### macOS / Linux

Deploy:

```bash
./cloudformation-fargate/cdeploy_cloudformation.sh --environment cfdemo --profile careconnect-sso
```

Teardown:

```bash
./cloudformation-fargate/cdestroy_cloudformation.sh --environment cfdemo --profile careconnect-sso
```



#### Notes

- Deploy scripts create or update the four stacks in order
- Deploy scripts build the backend Docker image and push it to ECR
- Teardown scripts delete stacks in dependency order and empty the ECR repository before removing the platform stack
- `cdeploy_cloudformation.ps1` and `cdeploy_cloudformation.sh` skip Maven tests by default; use `-RunTests` in PowerShell or `--run-tests` in bash if you want tests included
- `cdestroy_cloudformation.ps1` and `cdestroy_cloudformation.sh` support skipping ECR cleanup with `-SkipEcrCleanup` or `--skip-ecr-cleanup`



### GitHub Actions Backend Deploy

For normal backend code changes, you do not need to redeploy networking, data,
and platform every time.

This repo also includes an app-only deploy path:

- `.github/workflows/backend-app-deploy.yml`
- `cdeploy_app_only.ps1`
- `cdeploy_app_only.sh`

That flow:

1. builds the backend jar
2. builds and pushes a uniquely tagged Docker image to ECR
3. updates only the ECS service stack



#### Current GitHub storage split

The current app-only workflow uses GitHub repository variables for the
non-secret values it needs:

- `AWS_GITHUB_ACTIONS_ROLE_ARN`
- `AWS_REGION`
- `CF_ENVIRONMENT`

The full deploy path uses GitHub repository secrets for the sensitive data-stack
values:

- `DEV_DATABASE_MASTER_PASSWORD`
- `DEV_JWT_SECRET`
- `CFDEMO_DATABASE_MASTER_PASSWORD`
- `CFDEMO_JWT_SECRET`

The full deploy scripts read those values from environment variables:

- `CARECONNECT_DATABASE_MASTER_PASSWORD`
- `CARECONNECT_JWT_SECRET`

That keeps real data-stack secrets out of committed parameter files.

### GitHub Actions Full Deploy

This repo also includes a manual full-deploy workflow:

- `.github/workflows/backend-full-deploy.yml`

Use it when you want GitHub Actions to create or update the full environment:

1. networking
2. data
3. platform
4. backend image build and push
5. service

This workflow is intentionally manual-only because it can create long-lived AWS
infrastructure and consumes GitHub Secrets for the data stack.

#### AWS setup click-by-click

What you are creating:

- one IAM identity provider for GitHub Actions
- one IAM role that GitHub Actions is allowed to assume



##### Create the GitHub OIDC identity provider

1. Sign in to the AWS Console
2. Search for `IAM`
3. Open `IAM`
4. In the left sidebar, click `Identity providers`
5. Check whether this provider already exists:
  - `https://token.actions.githubusercontent.com`
6. If it already exists, keep it and move to the IAM role steps
7. If it does not exist, click `Add provider`
8. For `Provider type`, choose:
  - `OpenID Connect`
9. For `Provider URL`, enter:
  - `https://token.actions.githubusercontent.com`
10. For `Audience`, enter:
  - `sts.amazonaws.com`
11. Click `Add provider`



##### Create the IAM role for GitHub Actions

1. In IAM, click `Roles`
2. Click `Create role`
3. For `Trusted entity type`, choose:
  - `Web identity`
4. For `Identity provider`, choose:
  - `token.actions.githubusercontent.com`
5. For `Audience`, choose:
  - `sts.amazonaws.com`
6. Continue to the permissions step
7. Search for:
  - `PowerUserAccess`
8. Check `PowerUserAccess`
9. Continue to the naming step
10. For role name, enter:
  - `careconnect-github-actions-deploy`
11. Click `Create role`



##### Finish the role configuration

1. Open the new role:
  - `careconnect-github-actions-deploy`
2. Open the `Trust relationships` tab
3. Click `Edit trust policy`
4. Replace the default trust policy with the GitHub OIDC trust policy from
  `[GITHUB_ACTIONS_SETUP.md](C:/Dev/SWEN670/2026_spring_careconnect/cloudformation-fargate/GITHUB_ACTIONS_SETUP.md)`
5. Replace:
  - `<account-id>`
  - branch names if needed
  - repo owner if needed
6. Click `Update policy`
7. Back on the role page, click `Add permissions`
8. Click `Create inline policy`
9. Open the `JSON` tab
10. Paste the `iam:PassRole` policy from
  `[GITHUB_ACTIONS_SETUP.md](C:/Dev/SWEN670/2026_spring_careconnect/cloudformation-fargate/GITHUB_ACTIONS_SETUP.md)`
11. Replace:
  - `<account-id>`
12. Save the inline policy



##### What to copy into GitHub

After the role is ready, copy the role ARN. It will look like:

- `arn:aws:iam::<account-id>:role/careconnect-github-actions-deploy`

You will use that value in GitHub as:

- `AWS_GITHUB_ACTIONS_ROLE_ARN`

The full setup guide is in
`[GITHUB_ACTIONS_SETUP.md](C:/Dev/SWEN670/2026_spring_careconnect/cloudformation-fargate/GITHUB_ACTIONS_SETUP.md)`.

### What each stack owns

1. `01-networking.yaml`

- VPC
- public subnets for ALB and ECS
- private subnets for RDS
- route tables
- internet gateway
- ALB / ECS / RDS security groups

1. `02-data.yaml`

- PostgreSQL RDS instance
- DB subnet group
- Secrets Manager secret for DB password
- Secrets Manager secret for JWT secret

1. `03-platform.yaml`

- ECR repository
- ECS cluster
- ECS task execution role
- ECS task role
- CloudWatch log group for the backend container

1. `04-service.yaml`

- Application Load Balancer
- target group
- listener
- ECS task definition
- ECS service
- app environment variable and secret wiring



### Design choices

- ALB is public on HTTP port `80`
- ECS tasks run in public subnets with public IPs enabled to avoid NAT costs
- RDS runs in private subnets
- Database and application secrets are stored in Secrets Manager
- ECS task execution role reads secrets and writes logs



### Required application contract

The templates assume the backend uses these environment variables:

- `SPRING_PROFILES_ACTIVE`
- `SERVER_PORT`
- `JDBC_URI`
- `DB_USER`
- `DB_PASSWORD`
- `SECURITY_JWT_SECRET`
- `APP_FRONTEND_BASE_URL`
- `CORS_ALLOWED_LIST`
- `SPRING_FLYWAY_ENABLED`
- `SPRING_JPA_HIBERNATE_DDL_AUTO`

The ALB health check path is:

- `/v1/api/test/health`



### Parameter files

Parameter files live under `[parameters](2026_spring_careconnect/cloudformation-fargate/parameters)`.
Because JSON does not support inline comments, the detailed parameter guide is
in `[parameters/README.md](2026_spring_careconnect/cloudformation-fargate/parameters/README.md)`.

For the data stack specifically:

- committed `*-data.json` files contain placeholders only
- real secret values should be injected through:
  - `CARECONNECT_DATABASE_MASTER_PASSWORD`
  - `CARECONNECT_JWT_SECRET`
  - or the manual GitHub full-deploy workflow that maps repository secrets into
  those variables
- `BackendImageUri` in `*-service.json` is normally overridden by the deploy
scripts or GitHub Actions workflow



### Example deploy commands

Create the networking stack:

```powershell
aws cloudformation create-stack `
  --stack-name careconnect-networking-dev `
  --template-body file://.\templates\01-networking.yaml `
  --parameters file://.\parameters\dev-networking.json `
  --capabilities CAPABILITY_NAMED_IAM
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --stack-name careconnect-networking-dev \
  --template-body file://./templates/01-networking.yaml \
  --parameters file://./parameters/dev-networking.json \
  --capabilities CAPABILITY_NAMED_IAM
```

Create the data stack:

```powershell
aws cloudformation create-stack `
  --stack-name careconnect-data-dev `
  --template-body file://.\templates\02-data.yaml `
  --parameters file://.\parameters\dev-data.json `
  --capabilities CAPABILITY_NAMED_IAM
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --stack-name careconnect-data-dev \
  --template-body file://./templates/02-data.yaml \
  --parameters file://./parameters/dev-data.json \
  --capabilities CAPABILITY_NAMED_IAM
```

Create the platform stack:

```powershell
aws cloudformation create-stack `
  --stack-name careconnect-platform-dev `
  --template-body file://.\templates\03-platform.yaml `
  --parameters file://.\parameters\dev-platform.json `
  --capabilities CAPABILITY_NAMED_IAM
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --stack-name careconnect-platform-dev \
  --template-body file://./templates/03-platform.yaml \
  --parameters file://./parameters/dev-platform.json \
  --capabilities CAPABILITY_NAMED_IAM
```

Get the repository URI:

```powershell
aws cloudformation describe-stacks `
  --stack-name careconnect-platform-dev `
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" `
  --output text
```

macOS / Linux:

```bash
aws cloudformation describe-stacks \
  --stack-name careconnect-platform-dev \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" \
  --output text
```

Build and push the backend image after packaging the jar (must be done from backend/core of your repository):

```powershell
cd C:\Dev\SWEN670\2026_spring_careconnect\backend\core
.\mvnw.cmd clean package -Pdocker -DskipTests

$REGION = "us-east-1"
$ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text).Trim()
$IMAGE_URI = "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/careconnect-backend:dev"

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
docker build -t careconnect-backend:dev .
docker tag careconnect-backend:dev $IMAGE_URI
docker push $IMAGE_URI
```

macOS / Linux:

```bash
cd /path/to/2026_spring_careconnect/backend/core
./mvnw clean package -Pdocker -DskipTests

REGION="us-east-1"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/careconnect-backend:dev"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
docker build -t careconnect-backend:dev .
docker tag careconnect-backend:dev "$IMAGE_URI"
docker push "$IMAGE_URI"
```

Create the service stack:

```powershell
aws cloudformation create-stack `
  --stack-name careconnect-service-dev `
  --template-body file://.\templates\04-service.yaml `
  --parameters `
    ParameterKey=Environment,ParameterValue=dev `
    ParameterKey=BackendImageUri,ParameterValue="$IMAGE_URI" `
    ParameterKey=SpringProfile,ParameterValue=dev `
    ParameterKey=FrontendBaseUrl,ParameterValue=http://localhost:3000 `
    ParameterKey=CorsAllowedList,ParameterValue="http://localhost:*,http://127.0.0.1:*" `
    ParameterKey=ContainerPort,ParameterValue=8081 `
    ParameterKey=DesiredCount,ParameterValue=1 `
    ParameterKey=TaskCpu,ParameterValue=1024 `
    ParameterKey=TaskMemory,ParameterValue=3072 `
    ParameterKey=HealthCheckPath,ParameterValue=/v1/api/test/health `
    ParameterKey=HealthCheckGracePeriodSeconds,ParameterValue=180 `
  --capabilities CAPABILITY_NAMED_IAM
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --stack-name careconnect-service-dev \
  --template-body file://./templates/04-service.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=BackendImageUri,ParameterValue="$IMAGE_URI" \
    ParameterKey=SpringProfile,ParameterValue=dev \
    ParameterKey=FrontendBaseUrl,ParameterValue=http://localhost:3000 \
    ParameterKey=CorsAllowedList,ParameterValue="http://localhost:*,http://127.0.0.1:*" \
    ParameterKey=ContainerPort,ParameterValue=8081 \
    ParameterKey=DesiredCount,ParameterValue=1 \
    ParameterKey=TaskCpu,ParameterValue=1024 \
    ParameterKey=TaskMemory,ParameterValue=3072 \
    ParameterKey=HealthCheckPath,ParameterValue=/v1/api/test/health \
    ParameterKey=HealthCheckGracePeriodSeconds,ParameterValue=180 \
  --capabilities CAPABILITY_NAMED_IAM
```

Get the ALB DNS name:

```powershell
aws cloudformation describe-stacks `
  --stack-name careconnect-service-dev `
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDnsName'].OutputValue" `
  --output text
```

macOS / Linux:

```bash
aws cloudformation describe-stacks \
  --stack-name careconnect-service-dev \
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDnsName'].OutputValue" \
  --output text
```

Run the frontend against the deployed backend:

```powershell
flutter run --dart-define=BACKEND_URL=http://<alb-dns-name>
```

macOS / Linux:

```bash
flutter run --dart-define=BACKEND_URL=http://<alb-dns-name>
```



### macOS / Linux translation

The step-by-step walkthrough below includes direct macOS/Linux command blocks
next to the PowerShell versions. Use those commands directly.

Quick shell translation reference:

- PowerShell env vars like `$Env:AWS_PROFILE = "careconnect-sso"` become:
  - `export AWS_PROFILE="careconnect-sso"`
- PowerShell line continuation uses ``` while `bash` / `zsh` use `\`
- Windows Maven wrapper `.\mvnw.cmd` becomes `./mvnw`
- PowerShell `Invoke-RestMethod` becomes `curl`
- PowerShell `Remove-Item Env:...` becomes `unset ...`
- Windows paths like `C:\Dev\...` become either your own absolute Unix path or
relative paths from the repo root

Minimal `bash` example:

```bash
export AWS_PROFILE="careconnect-sso"
aws sso login --profile careconnect-sso

aws cloudformation create-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-networking-cfdemo \
  --template-body file://$(pwd)/cloudformation-fargate/templates/01-networking.yaml \
  --parameters file://$(pwd)/cloudformation-fargate/parameters/cfdemo-networking.json \
  --capabilities CAPABILITY_NAMED_IAM
```



### Parallel environment pattern

To test changes without touching an existing environment:

1. copy the `dev-*.json` parameter files
2. create a new environment name like `cfdemo`
3. use unique stack names such as:

- `careconnect-networking-cfdemo`
- `careconnect-data-cfdemo`
- `careconnect-platform-cfdemo`
- `careconnect-service-cfdemo`

1. use a distinct ECR image tag such as `cfdemo`

This keeps the old and new ALBs, ECS services, clusters, and databases
separate.

### Student Walkthrough: `cfdemo`

This is the shortest working path for a second, parallel deployment that does
not interfere with an existing manual Fargate environment.

#### 1. Log in to AWS CLI

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
aws sso login --profile careconnect-sso
aws sts get-caller-identity --profile careconnect-sso
```

macOS / Linux:

```bash
export AWS_PROFILE="careconnect-sso"
aws sso login --profile careconnect-sso
aws sts get-caller-identity --profile careconnect-sso
```



#### 2. Update parameter placeholders

Replace the placeholder values in:

- `[parameters/cfdemo-data.json](2026_spring_careconnect/cloudformation-fargate/parameters/cfdemo-data.json)`
- `[parameters/cfdemo-service.json](SWEN670/2026_spring_careconnect/cloudformation-fargate/parameters/cfdemo-service.json)`

At minimum, set:

- a real PostgreSQL password
- a real JWT secret
- the final ECR image URI after the image push step



#### 3. Create the networking stack

```powershell
aws cloudformation create-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-networking-cfdemo `
  --template-body file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\templates\01-networking.yaml `
  --parameters file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\parameters\cfdemo-networking.json `
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-networking-cfdemo
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-networking-cfdemo \
  --template-body file://$(pwd)/cloudformation-fargate/templates/01-networking.yaml \
  --parameters file://$(pwd)/cloudformation-fargate/parameters/cfdemo-networking.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-networking-cfdemo
```



#### 4. Create the data stack

```powershell
aws cloudformation create-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-data-cfdemo `
  --template-body file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\templates\02-data.yaml `
  --parameters file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\parameters\cfdemo-data.json `
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-data-cfdemo
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-data-cfdemo \
  --template-body file://$(pwd)/cloudformation-fargate/templates/02-data.yaml \
  --parameters file://$(pwd)/cloudformation-fargate/parameters/cfdemo-data.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-data-cfdemo
```



#### 5. Create the platform stack

```powershell
aws cloudformation create-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo `
  --template-body file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\templates\03-platform.yaml `
  --parameters file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\parameters\cfdemo-platform.json `
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo \
  --template-body file://$(pwd)/cloudformation-fargate/templates/03-platform.yaml \
  --parameters file://$(pwd)/cloudformation-fargate/parameters/cfdemo-platform.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo
```



#### 6. Get the `cfdemo` ECR repository URI

```powershell
aws cloudformation describe-stacks `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo `
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" `
  --output text
```

macOS / Linux:

```bash
aws cloudformation describe-stacks \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" \
  --output text
```

Expected shape:

```text
331738867837.dkr.ecr.us-east-1.amazonaws.com/careconnect-backend-cfdemo
```



#### 7. Build the backend jar

```powershell
cd C:\Dev\SWEN670\2026_spring_careconnect\backend\core
.\mvnw.cmd clean package -Pdocker -DskipTests
```

macOS / Linux:

```bash
cd /path/to/2026_spring_careconnect/backend/core
./mvnw clean package -Pdocker -DskipTests
```



#### 8. Build and push the `cfdemo` Docker image

```powershell
$Env:AWS_PROFILE = "careconnect-sso"

$REGION = "us-east-1"
$ACCOUNT_ID = (aws sts get-caller-identity --profile careconnect-sso --query Account --output text).Trim()
$REPO = "careconnect-backend-cfdemo"
$TAG = "cfdemo"
$IMAGE_URI = "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO`:$TAG"

aws ecr get-login-password --profile careconnect-sso --region $REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
docker build -t "$REPO`:$TAG" .
docker tag "$REPO`:$TAG" "$IMAGE_URI"
docker push "$IMAGE_URI"

$IMAGE_URI
```

macOS / Linux:

```bash
export AWS_PROFILE="careconnect-sso"

REGION="us-east-1"
ACCOUNT_ID="$(aws sts get-caller-identity --profile careconnect-sso --query Account --output text)"
REPO="careconnect-backend-cfdemo"
TAG="cfdemo"
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$TAG"

aws ecr get-login-password --profile careconnect-sso --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
docker build -t "$REPO:$TAG" .
docker tag "$REPO:$TAG" "$IMAGE_URI"
docker push "$IMAGE_URI"

echo "$IMAGE_URI"
```

Expected image URI:

```text
331738867837.dkr.ecr.us-east-1.amazonaws.com/careconnect-backend-cfdemo:cfdemo
```



#### 9. Update `cfdemo-service.json`

Set `BackendImageUri` in
`[parameters/cfdemo-service.json](2026_spring_careconnect/cloudformation-fargate/parameters/cfdemo-service.json)`
to the full URI printed in the previous step.

#### 10. Create the service stack

```powershell
aws cloudformation create-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --template-body file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\templates\04-service.yaml `
  --parameters file://C:\Dev\SWEN670\2026_spring_careconnect\cloudformation-fargate\parameters\cfdemo-service.json `
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-service-cfdemo
```

macOS / Linux:

```bash
aws cloudformation create-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-service-cfdemo \
  --template-body file://$(pwd)/cloudformation-fargate/templates/04-service.yaml \
  --parameters file://$(pwd)/cloudformation-fargate/parameters/cfdemo-service.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-service-cfdemo
```



#### 11. Get the ALB DNS name

```powershell
aws cloudformation describe-stacks `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-service-cfdemo `
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDnsName'].OutputValue" `
  --output text
```

macOS / Linux:

```bash
aws cloudformation describe-stacks \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-service-cfdemo \
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDnsName'].OutputValue" \
  --output text
```



#### 12. Test the backend health endpoint

```powershell
Invoke-RestMethod "http://<alb-dns-name>/v1/api/test/health"
```

macOS / Linux:

```bash
curl http://<alb-dns-name>/v1/api/test/health
```



#### 13. Run the frontend against the `cfdemo` backend

```powershell
cd C:\Dev\SWEN670\2026_spring_careconnect\frontend
flutter run --dart-define=BACKEND_URL=http://<alb-dns-name>
```

macOS / Linux:

```bash
cd /path/to/2026_spring_careconnect/frontend
flutter run --dart-define=BACKEND_URL=http://careconnect-cfdemo-alb-953043145.us-east-1.elb.amazonaws.com
```

Do not append `/v1` to `BACKEND_URL`.

#### 14. If a stack fails

Use this to find the first failing resource:

```powershell
aws cloudformation describe-stack-events `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name <stack-name> `
  --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatusReason]" `
  --output table
```

macOS / Linux:

```bash
aws cloudformation describe-stack-events \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name <stack-name> \
  --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatusReason]" \
  --output table
```



### Teardown: `cfdemo`

Use this order so dependencies are removed cleanly. Wait until each `wait`
command completes before continuing:

1. `careconnect-service-cfdemo`
2. `careconnect-platform-cfdemo`
3. `careconnect-data-cfdemo`
4. `careconnect-networking-cfdemo`



#### 1. Delete the service stack

```powershell
aws cloudformation delete-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-service-cfdemo

aws cloudformation wait stack-delete-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-service-cfdemo
```



#### 2. Delete the platform stack

```powershell
aws cloudformation delete-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo

aws cloudformation wait stack-delete-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo
```



#### 2a. If the platform stack deletion fails on the ECR repository

This happened during the real `cfdemo` teardown. The stack can enter
`DELETE_FAILED` if the ECR repository still contains tagged or untagged images.

First, check the failing resource:

```powershell
aws cloudformation describe-stack-events `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo `
  --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatusReason]" `
  --output table
```

If `BackendRepository` is the blocker, list the remaining images:

```powershell
aws ecr list-images `
  --profile careconnect-sso `
  --region us-east-1 `
  --repository-name careconnect-backend-cfdemo
```

Delete the tagged image first if it exists:

```powershell
aws ecr batch-delete-image `
  --profile careconnect-sso `
  --region us-east-1 `
  --repository-name careconnect-backend-cfdemo `
  --image-ids imageTag=cfdemo
```

If untagged images remain, delete them by digest using the real values returned
by `list-images`:

```powershell
aws ecr batch-delete-image `
  --profile careconnect-sso `
  --region us-east-1 `
  --repository-name careconnect-backend-cfdemo `
  --image-ids imageDigest=sha256:sha256:e1dc629030f58bd5c2db35fa5b83084afd4437bc675443fb82e5f79d425a7f00 imageDigest=sha256:sha256:0b1fea9aa2d457a32bb5d6ef0a59530f7f5d0c99c0eaaefc51053e3c90bea1bf
```

Confirm the repository is empty:

```powershell
aws ecr list-images `
  --profile careconnect-sso `
  --region us-east-1 `
  --repository-name careconnect-backend-cfdemo
```

You want:

```json
{
  "imageIds": []
}
```

Then retry deleting the platform stack:

```powershell
aws cloudformation delete-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo

aws cloudformation wait stack-delete-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-platform-cfdemo
```



#### 3. Delete the data stack

```powershell
aws cloudformation delete-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-data-cfdemo

aws cloudformation wait stack-delete-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-data-cfdemo
```



#### 4. Delete the networking stack

```powershell
aws cloudformation delete-stack `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-networking-cfdemo

aws cloudformation wait stack-delete-complete `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-name careconnect-networking-cfdemo
```



#### Optional cleanup: remove the `cfdemo` ECR images before deleting the platform stack

If you want to proactively empty the repository before deleting the platform
stack:

```powershell
aws ecr batch-delete-image `
  --profile careconnect-sso `
  --region us-east-1 `
  --repository-name careconnect-backend-cfdemo `
  --image-ids imageTag=cfdemo
```

If `list-images` still shows untagged digests, remove those by digest too.

#### Optional cleanup: confirm nothing remains

```powershell
aws cloudformation list-stacks `
  --profile careconnect-sso `
  --region us-east-1 `
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED ROLLBACK_COMPLETE `
  --query "StackSummaries[?contains(StackName, 'cfdemo')].[StackName,StackStatus]" `
  --output table
```



### Important safety note

These teardown commands only target the parallel `cfdemo` stacks. They do not
touch an existing manual Fargate environment unless you intentionally reuse the
same stack names.

### macOS / Linux teardown translation

The teardown flow is identical on macOS and Linux. The only changes are shell
syntax and the use of `bash` / `zsh`-style commands.

#### 1. Set the AWS profile

```bash
export AWS_PROFILE="careconnect-sso"
```



#### 2. Delete the stacks in the same order

```bash
aws cloudformation delete-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-service-cfdemo

aws cloudformation wait stack-delete-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-service-cfdemo

aws cloudformation delete-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo

aws cloudformation wait stack-delete-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo

aws cloudformation delete-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-data-cfdemo

aws cloudformation wait stack-delete-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-data-cfdemo

aws cloudformation delete-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-networking-cfdemo

aws cloudformation wait stack-delete-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-networking-cfdemo
```



#### 3. If the platform stack fails because the ECR repository is not empty

Check the failing resource:

```bash
aws cloudformation describe-stack-events \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo \
  --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatusReason]" \
  --output table
```

List remaining images:

```bash
aws ecr list-images \
  --profile careconnect-sso \
  --region us-east-1 \
  --repository-name careconnect-backend-cfdemo
```

Delete the tagged image:

```bash
aws ecr batch-delete-image \
  --profile careconnect-sso \
  --region us-east-1 \
  --repository-name careconnect-backend-cfdemo \
  --image-ids imageTag=cfdemo
```

Delete any remaining untagged digests using the real values returned by
`list-images`:

```bash
aws ecr batch-delete-image \
  --profile careconnect-sso \
  --region us-east-1 \
  --repository-name careconnect-backend-cfdemo \
  --image-ids imageDigest=sha256:<digest-1> imageDigest=sha256:<digest-2>
```

Then retry deleting the platform stack:

```bash
aws cloudformation delete-stack \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo

aws cloudformation wait stack-delete-complete \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-name careconnect-platform-cfdemo
```



#### 4. Verify that no `cfdemo` stacks remain

```bash
aws cloudformation list-stacks \
  --profile careconnect-sso \
  --region us-east-1 \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED ROLLBACK_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'cfdemo')].[StackName,StackStatus]" \
  --output table
```



### Common Failure Modes

These are the issues that actually came up while building and testing the
parallel Fargate and CloudFormation environments.

#### 1. Expired AWS token

Symptoms:

- `ExpiredToken`
- `InvalidClientTokenId`
- AWS CLI commands fail even though they worked earlier

Fix:

```powershell
$Env:AWS_PROFILE = "careconnect-sso"
aws sso login --profile careconnect-sso
aws sts get-caller-identity --profile careconnect-sso
```

macOS / Linux:

```bash
export AWS_PROFILE="careconnect-sso"
aws sso login --profile careconnect-sso
aws sts get-caller-identity --profile careconnect-sso
```

If stale environment variables are interfering, clear them first:

```powershell
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
```

macOS / Linux:

```bash
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_PROFILE
```



#### 2. Missing `-Pdocker` during backend build

Symptoms:

- Docker build fails on:
  - `COPY target/careconnect-backend-0.0.1-SNAPSHOT.jar app.jar`
- JAR file not found in `target`

Cause:

- the default Maven profile in this repo builds the Lambda-oriented artifact,
not the Spring Boot fat jar used by Docker

Fix:

```powershell
cd C:\Dev\SWEN670\2026_spring_careconnect\backend\core
.\mvnw.cmd clean package -Pdocker -DskipTests
```

macOS / Linux:

```bash
cd /path/to/2026_spring_careconnect/backend/core
./mvnw clean package -Pdocker -DskipTests
```



#### 3. ECR repository name collision

Symptoms:

- CloudFormation platform stack rolls back
- error mentions:
  - `AWS::ECR::Repository`
  - `already exists`

Cause:

- repository names must be unique in the account and region

Fix:

- use a unique repository name for the parallel environment, for example:
  - `careconnect-backend-cfdemo`



#### 4. Stopped RDS instance

Symptoms:

- ECS task logs show:
  - `SQLState: 08001`
  - `The connection attempt failed`
  - `SocketTimeoutException: Connect timed out`

Cause:

- the PostgreSQL RDS instance was stopped, so ECS could not connect

Fix:

1. start the RDS instance
2. wait for status `Available`
3. force a new ECS deployment or retry the service



#### 5. ECS / RDS VPC mismatch

Symptoms:

- ECS task cannot connect to PostgreSQL
- security groups look correct, but RDS still times out

Cause:

- ECS tasks and RDS were created in different VPCs, so SG references and routing
do not form a valid path

Fix:

- ECS, ALB, and RDS must be in the same VPC
- the RDS security group should allow `5432` from the ECS task security group
- the ECS task security group must actually be attached to the running task



#### 6. Missing `http://` in `BACKEND_URL`

Symptoms:

- Flutter login or API requests fail with:
  - `No host specified in URI`

Cause:

- the frontend was launched with a host name only, without the scheme

Fix:

Use:

```powershell
flutter run --dart-define=BACKEND_URL=http://<alb-dns-name>
```

macOS / Linux:

```bash
flutter run --dart-define=BACKEND_URL=http://<alb-dns-name>
```

Do not use:

```text
cc-backend-alb-xxxx.us-east-1.elb.amazonaws.com
```

Do not append `/v1`, because the app already builds those paths.