# AWS access setup (start here)

Getting from "I can log into AWS in a browser" to "I can deploy this project."

If you already have a working `careconnect-sso` CLI profile, skip to the
[Student Walkthrough](./README.md#student-walkthrough-cfdemo).

> **Correction to an older doc.** [DEPLOY_2026_SUMMER.md §1](./DEPLOY_2026_SUMMER.md#1-prerequisites)
> says `careconnect-sso` is "only a local CLI label — not school SSO" and tells
> you to configure it with **IAM access keys** from your instructor. That is not
> how the working setup is configured. It is school SSO, and you do not need
> access keys to deploy. Follow this document instead.

---

## What you are getting

Each of us has our **own** AWS account through the school's SSO portal. That has
three consequences worth knowing before you start:

- **Your deploys are yours.** You are not sharing an environment, so you cannot
  break anyone else's, and nobody can break yours.
- **You pay for what you leave running.** A full CareConnect environment costs
  roughly **$50–60/month** if left up — Fargate and RDS are ~90% of it, and both
  bill hourly whether or not anyone uses them. A deploy-verify-destroy cycle
  costs well under a dollar. Tear down when you are done.
- **Nothing is pre-created in your account.** No stacks, no database, no ECR
  repository. The first deploy creates all of it.

---

## 1. Create the CLI profile

You need the AWS CLI v2 (`aws --version`). Then:

```bash
aws configure sso
```

Answer the prompts:

| Prompt | Value |
| ------ | ----- |
| SSO session name | `careconnect` |
| SSO start URL | `https://d-90679e4644.awsapps.com/start` |
| SSO region | `us-east-1` |
| SSO registration scopes | `sso:account:access` (accept the default) |

A browser window opens for you to authorize. After that the CLI lists the
account(s) you have access to — pick yours. Then:

| Prompt | Value |
| ------ | ----- |
| CLI default client region | `us-east-1` |
| CLI default output format | `json` |
| CLI profile name | `careconnect-sso` |

The profile name matters: **every script in this repo defaults to
`careconnect-sso`**. Name it anything else and you will be passing `--profile`
on every command.

## 2. Verify it worked

```bash
aws sts get-caller-identity --profile careconnect-sso
```

Expect something like:

```json
{
  "UserId": "AROA...:you@student.umgc.edu",
  "Account": "123456789012",
  "Arn": "arn:aws:sts::123456789012:assumed-role/AWSReservedSSO_StudentAdminAccess_.../you@student.umgc.edu"
}
```

The `assumed-role` and `AWSReservedSSO_` parts confirm SSO is working. If you
see `arn:aws:iam::...:user/...` instead, you are on access keys rather than SSO —
which also works, but is not what the school accounts hand out.

## 3. Refresh the session when it expires

SSO sessions are short-lived. When commands start failing with `ExpiredToken`,
`InvalidClientTokenId`, or `Token has expired and refresh failed`:

```bash
aws sso login --profile careconnect-sso
```

This is the single most common "AWS is broken" moment. It is not broken; the
token expired. Expect to run this at the start of each working session.

If stale environment variables are interfering, clear them first:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
```

---

## Do you need API keys?

Two different credential paths, and confusing them wastes time:

| What you are doing | Credentials |
| ------------------ | ----------- |
| Deploying stacks, reading logs, anything with the AWS CLI | **SSO** — the profile above. No keys. |
| Running the backend **locally** with video calls, recording, or AI features | An **IAM user with access keys** in `backend/core/.env`, because the local process needs Chime / Bedrock / Transcribe / S3 permissions and cannot assume the ECS task role |

Most work only needs the first. You need the second only if you are developing
against Chime, Bedrock, Transcribe, or S3 from your own machine — see
[TEAM_A_VIDEO_CALL_QUICKSTART.md](../docs/guides/TEAM_A_VIDEO_CALL_QUICKSTART.md)
§3a for the policy set.

Deployed environments never use access keys. ECS tasks assume
`careconnect-{env}-ecsTaskRole`, and GitHub Actions uses OIDC.

---

## 4. Deploy something

Go to the [Student Walkthrough](./README.md#student-walkthrough-cfdemo) and
start at step 0 (toolchain check). Budget about 20 minutes for a first deploy;
most of it is RDS.

When you are finished, tear it down:

```bash
./cloudformation-fargate/cdestroy_cloudformation.sh --environment cfdemo --profile careconnect-sso
```

Then confirm nothing survived — see
[Teardown](./README.md#teardown-cfdemo). RDS and Fargate are the two that cost
money, so those are the ones worth checking.

---

## Testing against a `prod` Spring profile

Both `dev-service.json` and `cfdemo-service.json` set `SpringProfile=dev`. Some
behaviour differs meaningfully between profiles — the telemetry endpoints in
particular behave differently, so **a dev-profile environment cannot verify a
prod-profile fix in either direction**.

To get a prod-profile environment, set `SpringProfile` to `prod` in
`parameters/cfdemo-service.json` and redeploy the service stack:

```bash
./cloudformation-fargate/cdeploy_app_only.sh --environment cfdemo --profile careconnect-sso
```

RDS lives in the `02-data` stack and survives a service-stack redeploy, so any
seeded data persists across the flip. That gives you a same-environment,
same-data before/after.

**Not yet proven end to end.** The prod profile pulls configuration from SSM
(`/careconnect/{env}/*`) and expects a SendGrid API key for email. Expect to
resolve some configuration before it comes up cleanly, and add what you learn to
this section.

---

## When something fails

- Deploy and teardown failures: [Common Failure Modes](./README.md#common-failure-modes)
- Stack-specific errors: `aws cloudformation describe-stack-events --stack-name <name> --profile careconnect-sso --region us-east-1 --query "StackEvents[?contains(ResourceStatus,'FAILED')].[LogicalResourceId,ResourceStatusReason]" --output table`
- Backend container logs: CloudWatch log group `/ecs/careconnect-backend-{env}`
