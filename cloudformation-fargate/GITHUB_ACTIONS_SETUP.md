# GitHub Actions Backend Deploy Setup

This guide covers the lightweight CI/CD path for the `cloudformation-fargate`
backend deployment.

The goal is:

1. developer pushes backend changes to GitHub
2. GitHub Actions builds the backend Docker image
3. GitHub Actions pushes the image to ECR with a unique tag
4. GitHub Actions updates only the ECS service stack

This setup does **not** recreate networking, data, or platform resources on
every backend push. Those long-lived stacks should be created once with the full
deploy script and then left in place.

## Current Storage Split

For the current repo setup, we split values like this:

- GitHub repository variables:
  - `AWS_GITHUB_ACTIONS_ROLE_ARN`
  - `AWS_REGION`
  - `CF_ENVIRONMENT`
- committed parameter JSON:
  - non-sensitive networking, platform, and service settings
- GitHub repository secrets for full deploys:
  - `DEV_DATABASE_MASTER_PASSWORD`
  - `DEV_JWT_SECRET`
  - `CFDEMO_DATABASE_MASTER_PASSWORD`
  - `CFDEMO_JWT_SECRET`

The current app-only GitHub Actions workflow does **not** need the database
password or JWT secret, so those repository secrets are only used by the manual
full-deploy workflow path.

## Files Added For This Flow

- `.github/workflows/backend-app-deploy.yml`
- `.github/workflows/backend-full-deploy.yml`
- `cloudformation-fargate/cdeploy_app_only.sh`
- `cloudformation-fargate/cdeploy_app_only.ps1`

## How This Differs From The Full Deploy Scripts

Use the full deploy scripts when:

- creating a new environment for the first time
- changing VPC, database, ECR, ECS cluster, or IAM resources

Use the app-only deploy scripts when:

- backend code changed
- Docker image contents changed
- ECS service settings changed in `04-service.yaml`
- service parameter values changed in `parameters/*-service.json`

The manual full-deploy workflow uses:

- `cloudformation-fargate/cdeploy_cloudformation.sh`
- repository secrets for the data stack

The app-only workflow uses:

- `cloudformation-fargate/cdeploy_app_only.sh`
- repository variables only

## 1. Deploy The Environment Once First

Before GitHub Actions can do app-only deploys, the target environment must
already exist. The app-only workflow expects:

- `careconnect-platform-<environment>` to exist
- the ECR repository output to exist
- the ECS service stack to be creatable or updatable

Example local one-time deploy:

```powershell
.\cloudformation-fargate\cdeploy_cloudformation.ps1 -Environment dev -Profile careconnect-sso
```

or:

```bash
./cloudformation-fargate/cdeploy_cloudformation.sh --environment dev --profile careconnect-sso
```

## 2. Configure AWS Authentication For GitHub Actions

The recommended setup is GitHub OIDC with an IAM role. This avoids storing long
term AWS keys in the repository.

There are two ways to create it. Both produce the same provider and role, and
you only need one.

### 2-CFN. CloudFormation instead of the console (faster)

`templates/github-oidc-deploy-role.yaml` creates the OIDC provider and the
deploy role in one stack. It replaces sections 2a, 2b, and 2c below. Skip
straight to section 3 once it completes.

Run it **once per AWS account** that CI deploys into. Under per-user LEO
accounts that means each environment owner runs it in their own account and
hands the resulting role ARN to whoever administers the repository.

```bash
aws cloudformation deploy \
  --stack-name careconnect-github-oidc \
  --template-file cloudformation-fargate/templates/github-oidc-deploy-role.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --profile careconnect-sso
```

Then read the role ARN for section 3:

```bash
aws cloudformation describe-stacks \
  --stack-name careconnect-github-oidc \
  --query 'Stacks[0].Outputs[?OutputKey==`DeployRoleArn`].OutputValue' \
  --output text \
  --region us-east-1 --profile careconnect-sso
```

Parameters worth knowing before you run it:

| Parameter | Default | When to change it |
| --------- | ------- | ----------------- |
| `CreateOidcProvider` | `Yes` | Set to `No` if the account already has a `token.actions.githubusercontent.com` provider. Only one is allowed per account, and the stack fails with `EntityAlreadyExists` otherwise. Check first with the console steps in 2a. |
| `GitHubOrg` / `GitHubRepo` | `umgc` / `2026_fall_careconnect` | Change if you deploy from a fork. The trust policy will not match otherwise. |
| `PrimaryBranch` | `main` | The branch allowed to deploy without a GitHub Environment. |
| `DeployEnvironment1-4` | `dev`, `cfdemo`, `staging`, `prod` | The GitHub Environments allowed to assume the role. Named explicitly rather than wildcarded, so an environment you have not listed cannot deploy. Set a slot to `''` to allow nothing for it. |
| `AllowInfrastructureDeploy` | `No` | Set to `Yes` only in the account that runs `backend-full-deploy.yml`. `PowerUserAccess` cannot create the IAM task roles that `03-platform.yaml` needs. |

To change parameters, add `--parameter-overrides Key=Value ...` to the deploy
command. To tear it down: `aws cloudformation delete-stack --stack-name
careconnect-github-oidc`.

### 2-CONSOLE. Click-by-click in AWS

Use this path if you cannot run CloudFormation, or you want to watch each piece
being created.

1. Sign in to the AWS Console
2. In the top search bar, search for `IAM`
3. Click `IAM`
4. Keep this IAM area open because both the OIDC provider and the role are
   created here

What you are creating:

- one IAM identity provider for GitHub Actions
- one IAM role that GitHub Actions is allowed to assume

After both are created, that role ARN becomes the value you store in GitHub as:

- `AWS_GITHUB_ACTIONS_ROLE_ARN`

### 2a. Ensure The GitHub OIDC Provider Exists In AWS

If your AWS account does not already have the GitHub OIDC provider, create it
once in IAM for:

- `token.actions.githubusercontent.com`

Many accounts already have this configured.

#### Click-by-click: check whether the provider already exists

1. In the IAM left sidebar, click `Identity providers`
2. Look through the list for a provider with URL:
   - `https://token.actions.githubusercontent.com`
3. If you already see that provider:
   - stop here for this section
   - you do not need to create another one
4. If you do not see it:
   - continue with the steps below

#### Click-by-click: create the GitHub OIDC provider

1. On the `Identity providers` page, click `Add provider`
2. For `Provider type`, choose:
   - `OpenID Connect`
3. For `Provider URL`, enter:
   - `https://token.actions.githubusercontent.com`
4. For `Audience`, enter:
   - `sts.amazonaws.com`
5. Review the values carefully
6. Click `Add provider`

#### What you should see when finished

You should now have an IAM identity provider with:

- Provider type: `OpenID Connect`
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

### 2b. Create An IAM Role For GitHub Actions

Create a role that GitHub Actions can assume. A practical name is:

- `careconnect-github-actions-deploy`

Use a trust policy like this and replace the account details with your fork and
branch names:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:gjurado1/2026_spring_careconnect:ref:refs/heads/dev_gjurado_cloudformation",
            "repo:gjurado1/2026_spring_careconnect:ref:refs/heads/main",
            "repo:gjurado1/2026_spring_careconnect:ref:refs/heads/develop"
          ]
        }
      }
    }
  ]
}
```

If you plan to trigger the workflow from different branches, add them to the
`sub` list.

#### Click-by-click: create the IAM role

1. In the IAM left sidebar, click `Roles`
2. Click `Create role`
3. For `Trusted entity type`, choose:
   - `Web identity`
4. For `Identity provider`, choose:
   - `token.actions.githubusercontent.com`
5. For `Audience`, choose:
   - `sts.amazonaws.com`
6. If AWS shows GitHub-specific fields on this screen, enter:
   - `GitHub organization`: `gjurado1`
   - `GitHub repository`: `2026_spring_careconnect`
   - `GitHub branch`: `dev_gjurado_cloudformation`
7. Continue to the next step

At the permissions step, you can choose a practical first pass:

- attach `PowerUserAccess`

You will add a small inline `iam:PassRole` policy after the role is created.

8. In the permissions search box, search for:
   - `PowerUserAccess`
9. Check the box for `PowerUserAccess`
10. Continue to the next step
11. For the role name, enter:
    - `careconnect-github-actions-deploy`
12. Optionally add a description such as:
    - `Allows GitHub Actions in the CareConnect fork to deploy the backend app`
13. Click `Create role`

#### If AWS generated the trust policy automatically

AWS may auto-fill a trust policy from the GitHub organization, repository, and
branch values you entered on the role creation screen.

That is a good starting point, but we still want to review it after the role is
created so it matches the branches in this guide.

#### Click-by-click: update the trust relationship

After the role is created, replace the default trust relationship with the
policy shown above so the role is limited to your fork and allowed branches.

1. Open the new role:
   - `careconnect-github-actions-deploy`
2. Click the `Trust relationships` tab
3. Click `Edit trust policy`
4. Replace the existing JSON with the trust policy from this guide
5. In that JSON, replace:
   - `<account-id>`
   - branch names if needed
   - repo owner or repo name if they ever change
6. Click `Update policy`

#### Trust policy values to verify before saving

Make sure the trust policy contains:

- your AWS account ID in the OIDC provider ARN
- your fork owner:
  - `gjurado1`
- your repository name:
  - `2026_spring_careconnect`
- the allowed branches:
  - `dev_gjurado_cloudformation`
  - `main`
  - `develop`

The important `sub` values should look like:

```json
"token.actions.githubusercontent.com:sub": [
  "repo:gjurado1/2026_spring_careconnect:ref:refs/heads/dev_gjurado_cloudformation",
  "repo:gjurado1/2026_spring_careconnect:ref:refs/heads/main",
  "repo:gjurado1/2026_spring_careconnect:ref:refs/heads/develop"
]
```

#### What you should see when finished

Your role should now:

- exist in IAM as `careconnect-github-actions-deploy`
- trust `token.actions.githubusercontent.com`
- allow only your fork and approved branches to assume it

The role ARN will look like:

- `arn:aws:iam::<account-id>:role/careconnect-github-actions-deploy`

You will copy that ARN into GitHub later as:

- `AWS_GITHUB_ACTIONS_ROLE_ARN`

### 2c. Attach Permissions To The Role

For a first working student setup, the most practical path is:

- attach `PowerUserAccess`
- add an inline `iam:PassRole` permission for the ECS task roles

Example inline policy for `iam:PassRole`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::<account-id>:role/careconnect-*-ecsTaskExecutionRole",
        "arn:aws:iam::<account-id>:role/careconnect-*-ecsTaskRole"
      ]
    }
  ]
}
```

This is intentionally pragmatic for a student project. If you want to tighten
permissions later, start from the CloudTrail events generated by one successful
run and reduce the role from there.

#### Click-by-click: add the inline `iam:PassRole` policy

1. Open the role:
   - `careconnect-github-actions-deploy`
2. Make sure you are on the `Permissions` tab
2. Click `Add permissions`
3. Click `Create inline policy`
4. Click the `JSON` tab
5. Paste the `iam:PassRole` JSON policy from this guide
6. Replace:
   - `<account-id>`
7. Click `Next`
8. Give the policy a name, for example:
   - `careconnect-github-actions-passrole`
9. Click `Create policy`

#### What you should verify before leaving AWS

Before going back to GitHub, confirm all three are true:

1. the GitHub OIDC provider exists
2. the `careconnect-github-actions-deploy` role exists
3. the role has:
   - `PowerUserAccess`
   - the inline `iam:PassRole` policy
4. the `Trust relationships` tab includes:
   - `gjurado1/2026_spring_careconnect`
   - `dev_gjurado_cloudformation`
   - `main`
   - `develop`

## 3. Configure Repository Variables In Your Fork

In your fork, open:

- `Settings`
- `Secrets and variables`
- `Actions`
- `Variables`

Add these repository variables:

### Required variables

- `AWS_GITHUB_ACTIONS_ROLE_ARN`
  - Example: `arn:aws:iam::<account-id>:role/careconnect-github-actions-deploy`
- `AWS_REGION`
  - Example: `us-east-1`
- `CF_ENVIRONMENT`
  - Example: `dev`

`CF_ENVIRONMENT` is the default deployment target for push-triggered runs.

### Click-by-click in GitHub

#### Open the repository variables page

1. Open your fork in GitHub:
   - `https://github.com/gjurado1/2026_spring_careconnect`
2. Click `Settings`
3. In the left sidebar, click `Secrets and variables`
4. Click `Actions`
5. Click the `Variables` tab
6. Click `New repository variable`

#### Create `AWS_GITHUB_ACTIONS_ROLE_ARN`

1. In `Name`, enter:
   - `AWS_GITHUB_ACTIONS_ROLE_ARN`
2. In `Value`, enter your IAM role ARN, for example:
   - `arn:aws:iam::<account-id>:role/careconnect-github-actions-deploy`
3. Click `Add variable`

#### Create `AWS_REGION`

1. Click `New repository variable`
2. In `Name`, enter:
   - `AWS_REGION`
3. In `Value`, enter:
   - `us-east-1`
4. Click `Add variable`

#### Create `CF_ENVIRONMENT`

1. Click `New repository variable`
2. In `Name`, enter:
   - `CF_ENVIRONMENT`
3. In `Value`, enter the default environment the workflow should deploy to:
   - `dev`
4. Click `Add variable`

### What each variable does

- `AWS_GITHUB_ACTIONS_ROLE_ARN`
  - tells GitHub Actions which AWS IAM role to assume through OIDC
- `AWS_REGION`
  - tells the workflow which AWS region to deploy into
- `CF_ENVIRONMENT`
  - tells the workflow which CloudFormation environment to use by default on push

### What you should see when finished

Your repository variables list should contain at least:

- `AWS_GITHUB_ACTIONS_ROLE_ARN`
- `AWS_REGION`
- `CF_ENVIRONMENT`

## 4. Review The Workflow Branch Triggers

The workflow currently listens on:

- `main`
- `develop`
- `dev_gjurado_cloudformation`

If your fork uses different branch names, update:

- `.github/workflows/backend-app-deploy.yml`

Specifically this section:

```yaml
on:
  push:
    branches:
      - main
      - develop
      - dev_gjurado_cloudformation
```

## 5. Understand Image Tagging

The workflow intentionally uses unique image tags.

By default it builds tags like:

- `dev-1a2b3c4`
- `cfdemo-1a2b3c4`

That gives you:

- traceability from ECR image back to commit
- cleaner rollback history
- less ambiguity than reusing the same static `dev` tag forever

## 6. Test The Workflow

### Option A. Manual test from GitHub

Open:

- `Actions`
- `Backend App Deploy`
- `Run workflow`

Choose:

- branch
- environment
- optional image tag

Then start the run.

#### Click-by-click: run the workflow manually

1. Open your fork in GitHub:
   - `https://github.com/gjurado1/2026_spring_careconnect`
2. Click the `Actions` tab
3. In the left workflow list, click:
   - `Backend App Deploy`
4. Click the `Run workflow` button
5. In the branch dropdown, choose:
   - `dev_gjurado_cloudformation`
6. In the `environment` input, leave:
   - `dev`
   - or choose the environment you already deployed with the full script
7. In the `image_tag` input:
   - leave it blank for the default commit-based tag
   - or enter a temporary test tag if you want to recognize it easily in ECR
8. Click `Run workflow`

#### What you should see on the screen

After you click `Run workflow`, GitHub should:

- add a new workflow run near the top of the page
- show the run status as:
  - `Queued`, then
  - `In progress`

If you click into the run, you should see one job:

- `Build Push and Update ECS Service`

Inside that job, the steps should appear in this order:

1. `Checkout code`
2. `Determine deployment settings`
3. `Configure AWS credentials`
4. `Set up Java 17`
5. `Make deploy script executable`
6. `Build backend image and update ECS service`

### Option B. Automatic test from a push

Make a small backend change under:

- `backend/`

Then push that branch. The workflow should:

1. assume the AWS role through OIDC
2. build the Spring Boot jar with `-Pdocker`
3. build the Docker image
4. push the image to the environment ECR repository
5. update `careconnect-service-<environment>`

#### Click-by-click: trigger a run from a push

1. Make a small backend change in your local repo under:
   - `backend/`
2. Save the change
3. Commit it:

```powershell
git add .
git commit -m "Test backend app deploy workflow"
```

4. Push it to your fork on a workflow-enabled branch:

```powershell
git push origin dev_gjurado_cloudformation
```

5. Open your fork in GitHub
6. Click the `Actions` tab
7. Click:
   - `Backend App Deploy`

#### What you should see on the screen

After the push reaches GitHub, you should see:

- a new workflow run automatically appear
- the branch name shown as:
  - `dev_gjurado_cloudformation`
- the status move from:
  - `Queued` to `In progress`

If nothing appears:

- confirm the push went to a branch listed in the workflow
- confirm the changed files matched one of the workflow `paths`

## 7. What Success Looks Like

After a successful run, check:

- the workflow log in GitHub Actions
- the ECR repository for a new image tag
- the ECS service for a new deployment
- the backend health endpoint

#### What success looks like in GitHub Actions

In the workflow run page, you should see:

- a green check mark for the workflow
- a green check mark for the job:
  - `Build Push and Update ECS Service`
- each step marked as completed

The most important confirmations in the log are:

- AWS credentials configured successfully
- backend jar build completed
- Docker image built successfully
- Docker image pushed to ECR
- CloudFormation service stack created or updated successfully

#### What success looks like in AWS

After the workflow finishes, you should be able to verify:

1. **ECR**
   - open Amazon ECR
   - open the repository for your environment
   - confirm a new image tag exists, such as:
     - `dev-1a2b3c4`

2. **CloudFormation**
   - open CloudFormation
   - open `careconnect-service-<environment>`
   - confirm the stack status is healthy, for example:
     - `UPDATE_COMPLETE`
     - or `CREATE_COMPLETE`

3. **ECS**
   - open ECS
   - open the cluster for your environment
   - open the backend service
   - confirm a new deployment appeared

4. **Application health**
   - call the health endpoint and confirm the backend responds

Example health check:

```powershell
Invoke-RestMethod "http://<alb-dns>/v1/api/test/health"
```

or:

```bash
curl "http://<alb-dns>/v1/api/test/health"
```

## 8. Troubleshooting

### `role-to-assume` fails

Usually means:

- role ARN variable is wrong
- trust policy does not match your fork repo or branch
- GitHub OIDC provider is missing

### ECR push fails

Usually means:

- platform stack for the target environment does not exist
- ECR repo name/output is missing
- IAM role permissions are too narrow

### Service deploy fails

Usually means:

- service stack parameters are invalid
- the service stack is in `ROLLBACK_COMPLETE`
- the ECS task definition or ALB health check settings are invalid

The app-only scripts already print recent failed CloudFormation events to make
this easier to debug.

## 9. Local Equivalent Commands

If you want to test the exact same flow outside GitHub Actions:

PowerShell:

```powershell
.\cloudformation-fargate\cdeploy_app_only.ps1 -Environment dev -Profile careconnect-sso
```

bash:

```bash
./cloudformation-fargate/cdeploy_app_only.sh --environment dev --profile careconnect-sso
```

Both scripts:

- build the jar
- build and push a uniquely tagged image
- update only the ECS service stack

## 10. Recommended Working Pattern

1. use the full deploy script once per environment
2. use the GitHub Actions workflow for normal backend pushes
3. reserve the full deploy script for infrastructure changes

That split keeps the pipeline faster and avoids touching networking and database
resources when the only change was backend code.
