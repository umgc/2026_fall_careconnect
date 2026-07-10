## Parameter Files

These files are JSON because the AWS CLI accepts them directly with:

```powershell
--parameters file://path-to-file.json
```

JSON does not support inline comments, so this file explains what each
parameter file is for and what values need to be replaced before deployment.

### Files

1. `dev-networking.json`
- baseline networking parameters for the `dev` environment

2. `dev-data.json`
- checked-in placeholder values for the `dev` environment data stack
3. `dev-platform.json`
- ECR repository name and log retention for the `dev` environment

4. `dev-service.json`
- image URI and service/runtime settings for the `dev` environment

5. `cfdemo-networking.json`
- networking parameters for the parallel CloudFormation demo environment

6. `cfdemo-data.json`
- checked-in placeholder values for the parallel CloudFormation demo environment data stack

7. `cfdemo-platform.json`
- ECR repository name and log retention for the parallel CloudFormation demo environment

8. `cfdemo-service.json`
- image URI and service/runtime settings for the parallel CloudFormation demo environment

9. `staging-*.json` / `prod-*.json`
- parameter sets for staging and production (SpringProfile `prod`, AI enabled, pgvector RDS)

### P0 Ask AI deploy unblock (Tasks 0.1)

These CloudFormation changes must be deployed **in stack order** for Bedrock chat and pgvector schema patches to work in ECS:

| Stack | Change |
|-------|--------|
| `02-data.yaml` | RDS parameter group allows `vector` extension (`rds.allowed_extensions`); PostgreSQL 17.6 |
| `03-platform.yaml` | ECS task role: `bedrock:InvokeModel*` + SSM read on `/careconnect/*` |
| `04-service.yaml` | `SpringProfile=prod`, `CARECONNECT_AI_ENABLED=true`, SendGrid/`FROM_EMAIL`, `ENVIRONMENT` for SSM |

**Existing RDS instances:** updating the data stack attaches a new parameter group; RDS may require a **reboot** before `CREATE EXTENSION vector` succeeds. After deploy, confirm in logs: `Schema patch applied: V2607071920 – enable pgvector extension`.

**SSM secrets (prod profile):** store under `/careconnect/<Environment>/` (e.g. `/careconnect/cfdemo/sendgrid-api-key`). See `SsmPropertySourceInitializer.java` for the full parameter list. **JWT and DB credentials are not loaded from SSM** — ECS injects `SECURITY_JWT_SECRET`, `DB_PASSWORD`, and `DB_USER` from Secrets Manager (data stack).

**SSM migration checklist (cfdemo / staging / prod cutover to SpringProfile `prod`):**

1. Copy or create parameters under `/careconnect/<Environment>/` before updating the service stack.
2. Minimum parameters for a smoke test:
   - `sendgrid-api-key`
   - `google-client-id`
   - `google-client-secret`
3. Optional but commonly needed: `stripe-secret-key`, `stripe-webhook-secret`, `firebase-service-account-key`, OAuth/Fitbit keys.
4. Leave `WebSocketApiGatewayEndpoint` empty in checked-in `*-service.json` files (same as `dev`).
   Set the real `wss://...` value at deploy time when the WebSocket API exists
   (maps to `AWS_WEBSOCKET_API_GATEWAY_ENDPOINT`). Do not use a placeholder string —
   it is treated as a fake URL.
5. After service stack update, confirm ECS logs: `SSM PropertySource initialized with N parameters`.

Example copy (adjust environment name and region):

```powershell
$Env = "cfdemo"
$Region = "us-east-1"
foreach ($Name in @("sendgrid-api-key","google-client-id","google-client-secret")) {
  $Val = aws ssm get-parameter --name "/careconnect/prod/$Name" --with-decryption --query Parameter.Value --output text --region $Region
  aws ssm put-parameter --name "/careconnect/$Env/$Name" --type SecureString --value $Val --overwrite --region $Region
}
```

**RDS reboot after pgvector parameter group (data stack update):**

```powershell
aws rds reboot-db-instance --db-instance-identifier careconnect-<Environment>-db
```

Wait for the instance to become `available`, then redeploy the ECS service and verify logs contain:
`Schema patch applied: V2607071920 – enable pgvector extension`.

**Bedrock:** enable model access in the AWS account (Model access in Bedrock console) for Nova, Claude, Titan Embed, and any inference profiles in use.

### Placeholders that must be replaced

#### In the GitHub Secrets or shell environment

- `DatabaseMasterPassword`
  - real PostgreSQL master password for the new RDS instance

- `JwtSecret`
  - long random string used by the backend for JWT signing

The checked-in `*-data.json` files should stay sanitized with placeholders so
real secrets are not committed to Git.

#### In `*-service.json`

- `BackendImageUri`
  - full ECR image URI including the tag
  - example:
    - `331738867837.dkr.ecr.us-east-1.amazonaws.com/careconnect-backend-cfdemo:cfdemo`
  - when you use the deploy scripts or the GitHub Actions app-only workflow,
    this value is usually overridden automatically after the Docker image is
    pushed to ECR

### Secret injection pattern

For local full deploys, export these environment variables before running the
deploy script:

- `CARECONNECT_DATABASE_MASTER_PASSWORD`
- `CARECONNECT_JWT_SECRET`

For GitHub Actions full deploys, keep the checked-in `*-data.json` files
sanitized and store the real values in repository secrets such as:

- `DEV_DATABASE_MASTER_PASSWORD`
- `DEV_JWT_SECRET`
- `CFDEMO_DATABASE_MASTER_PASSWORD`
- `CFDEMO_JWT_SECRET`

The full deploy workflow maps those repository secrets into:

- `CARECONNECT_DATABASE_MASTER_PASSWORD`
- `CARECONNECT_JWT_SECRET`

before calling the full deploy script.

### Runtime notes

- **`SpringProfile`:** use `prod` for `cfdemo`, `staging`, and `prod` (SSM, SendGrid, WebSocket AWS mode). Keep `dev` only for lightweight cloud experiments (`dev-service.json`).
- **`CareConnectAiEnabled`:** set to `true` in environments that need `AIChatController` and Bedrock chat (`cfdemo`, `staging`, `prod` parameter files).
- **`ContainerPort`** is `8081` because that is the working ECS port for this app.
- **`HealthCheckPath`** is `/v1/api/test/health` because that is the endpoint the
  ALB uses to determine task health.
- Database schema in ECS is **not** managed by Flyway. New production DDL must be added as
  idempotent patches in `SchemaPatchRunner` (and/or rely on Hibernate `ddl-auto=update`).
  Files under `backend/core/src/main/resources/db/migration/` remain the canonical SQL reference.
- **pgvector:** RDS PostgreSQL 15+ with the data stack parameter group; `SchemaPatchRunner` runs `CREATE EXTENSION vector` at startup.
- **Bedrock IAM:** ECS task role in `03-platform.yaml` grants `bedrock:InvokeModel` for Nova, Claude, Titan Embed v2, and Voxtral (see template for full list).

### Parallel deployment guidance

Use a separate environment name like `cfdemo` when you need a second deployment
that does not interfere with an existing manual environment.

Keep these unique across parallel environments:

- CloudFormation stack names
- ECR repository names, if you create per-environment repos
- Docker image tags
- Secrets values
