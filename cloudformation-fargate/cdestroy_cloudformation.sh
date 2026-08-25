#!/usr/bin/env bash

set -euo pipefail

START_TIME="$(date +%s)"

# Track the active stack/operation so the ERR trap can print useful context.
ENVIRONMENT="dev"
PROFILE="careconnect-sso"
REGION="us-east-1"
SKIP_ECR_CLEANUP="false"
CURRENT_STACK_NAME=""
CURRENT_OPERATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -p|--profile)
      PROFILE="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    --skip-ecr-cleanup)
      SKIP_ECR_CLEANUP="true"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./cdestroy_cloudformation.sh [options]

Options:
  -e, --environment <name>   Environment name: dev, cfdemo, staging, prod
  -p, --profile <profile>    AWS CLI profile (default: careconnect-sso)
  -r, --region <region>      AWS region (default: us-east-1)
      --skip-ecr-cleanup     Skip emptying the ECR repository before platform deletion
  -h, --help                 Show this help text
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$ENVIRONMENT" in
  dev|cfdemo|staging|prod) ;;
  *)
    echo "Unsupported environment '$ENVIRONMENT'. Use one of: dev, cfdemo, staging, prod." >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMETER_DIR="$SCRIPT_DIR/parameters"
PLATFORM_PARAMETERS="$PARAMETER_DIR/${ENVIRONMENT}-platform.json"

IN_MSYS="false"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    IN_MSYS="true"
    ;;
esac

STACK_PREFIX="careconnect"
SERVICE_STACK_NAME="${STACK_PREFIX}-service-${ENVIRONMENT}"
PLATFORM_STACK_NAME="${STACK_PREFIX}-platform-${ENVIRONMENT}"
DATA_STACK_NAME="${STACK_PREFIX}-data-${ENVIRONMENT}"
NETWORKING_STACK_NAME="${STACK_PREFIX}-networking-${ENVIRONMENT}"

step() {
  echo
  echo "==> $1"
}

elapsed_time_text() {
  local end_time
  end_time="$(date +%s)"
  local elapsed=$((end_time - START_TIME))
  printf '%02d:%02d:%02d' $((elapsed / 3600)) $(((elapsed % 3600) / 60)) $((elapsed % 60))
}

on_error() {
  local exit_code="$1"
  local line_number="$2"

  echo
  echo "Teardown failed." >&2
  echo "Exit code: $exit_code (line $line_number)" >&2
  echo "Elapsed time: $(elapsed_time_text)" >&2

  if [[ -n "$CURRENT_OPERATION" ]]; then
    echo "Last operation: $CURRENT_OPERATION" >&2
  fi

  if [[ -n "$CURRENT_STACK_NAME" ]] && stack_exists "$CURRENT_STACK_NAME"; then
    echo >&2
    echo "CloudFormation troubleshooting for stack '$CURRENT_STACK_NAME':" >&2
    write_stack_failure_details "$CURRENT_STACK_NAME" >&2 || true
    echo >&2
    echo "Manual command:" >&2
    echo "aws cloudformation describe-stack-events --profile \"$PROFILE\" --region \"$REGION\" --stack-name \"$CURRENT_STACK_NAME\" --query \"StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]\" --output table" >&2
  fi

  exit "$exit_code"
}

trap 'on_error $? $LINENO' ERR

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Required command not found in PATH: $name" >&2
    exit 1
  fi
}

command_runs() {
  local name="$1"
  shift

  if ! command -v "$name" >/dev/null 2>&1; then
    return 1
  fi

  "$name" "$@" >/dev/null 2>&1
}

aws_cli() {
  if [[ "$IN_MSYS" == "true" ]]; then
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' aws "$@"
  else
    aws "$@"
  fi
}

JSON_HELPER=""
JSON_HELPER_KIND=""

if command_runs python3 -c 'print("ok")'; then
  JSON_HELPER="python3"
  JSON_HELPER_KIND="python"
elif command_runs python -c 'print("ok")'; then
  JSON_HELPER="python"
  JSON_HELPER_KIND="python"
elif command_runs py -3 -c 'print("ok")'; then
  JSON_HELPER="py"
  JSON_HELPER_KIND="py"
elif command_runs node -e 'process.exit(0)'; then
  JSON_HELPER="node"
  JSON_HELPER_KIND="node"
elif command_runs jq --version; then
  JSON_HELPER="jq"
  JSON_HELPER_KIND="jq"
elif command_runs powershell.exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'; then
  JSON_HELPER="powershell.exe"
  JSON_HELPER_KIND="powershell"
fi

if [[ -z "$JSON_HELPER" ]]; then
  echo "No working JSON helper was found. Install python3, node, jq, or PowerShell and retry." >&2
  exit 1
fi

run_python_helper() {
  local parameter_file="$1"
  shift || true

  case "$JSON_HELPER_KIND" in
    py)
      py -3 - "$parameter_file" "$@"
      ;;
    python)
      "$JSON_HELPER" - "$parameter_file" "$@"
      ;;
    *)
      echo "Internal error: run_python_helper called for non-Python helper." >&2
      return 1
      ;;
  esac
}

stack_exists() {
  local stack_name="$1"
  aws_cli cloudformation describe-stacks \
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name" >/dev/null 2>&1
}

get_stack_status() {
  local stack_name="$1"
  aws_cli cloudformation describe-stacks \
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name" \
    --query "Stacks[0].StackStatus" \
    --output text 2>/dev/null || true
}

write_stack_failure_details() {
  local stack_name="$1"
  local stack_status
  stack_status="$(get_stack_status "$stack_name" | tr -d '\r')"

  if [[ -n "$stack_status" && "$stack_status" != "None" ]]; then
    echo "Stack status: $stack_status"
  fi

  echo "Recent failed CloudFormation events for '$stack_name':"
  aws_cli cloudformation describe-stack-events \
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name" \
    --query "StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]" \
    --output table || true
}

delete_stack() {
  local stack_name="$1"
  CURRENT_STACK_NAME="$stack_name"
  CURRENT_OPERATION="Deleting stack '$stack_name'"

  # Teardown should be safe to rerun. If a stack is already gone, skip it.
  if ! stack_exists "$stack_name"; then
    echo "Stack '$stack_name' does not exist. Skipping."
    return
  fi

  step "Deleting stack: $stack_name"
  aws_cli cloudformation delete-stack \
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name"

  aws_cli cloudformation wait stack-delete-complete \
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name"
}

get_repository_name() {
  local parameter_file="$1"

  if [[ ! -f "$parameter_file" ]]; then
    return 0
  fi

  case "$JSON_HELPER_KIND" in
    python|py)
      run_python_helper "$parameter_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    entries = json.load(fh)

for entry in entries:
    if str(entry.get("ParameterKey")) == "RepositoryName":
        print(str(entry.get("ParameterValue", "")))
        break
PY
      ;;
    node)
      node - "$parameter_file" <<'NODE'
const fs = require("fs");
const entries = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const entry of entries) {
  if (String(entry.ParameterKey) === "RepositoryName") {
    console.log(String(entry.ParameterValue || ""));
    break;
  }
}
NODE
      ;;
    jq)
      jq -r '.[] | select(.ParameterKey == "RepositoryName") | .ParameterValue' "$parameter_file"
      ;;
    powershell)
      {
        printf '%s\n' 'param([string]$ParameterFile)'
        printf '%s\n' '$entries = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json'
        printf '%s\n' 'foreach ($entry in $entries) {'
        printf '%s\n' '  if ([string]$entry.ParameterKey -eq "RepositoryName") {'
        printf '%s\n' '    Write-Output ([string]$entry.ParameterValue)'
        printf '%s\n' '    break'
        printf '%s\n' '  }'
        printf '%s\n' '}'
      } | powershell.exe -NoProfile -Command - "$parameter_file"
      ;;
    *)
      echo "Unsupported JSON helper kind: $JSON_HELPER_KIND" >&2
      return 1
      ;;
  esac
}

ecr_repo_exists() {
  local repository_name="$1"
  aws_cli ecr describe-repositories \
    --profile "$PROFILE" \
    --region "$REGION" \
    --repository-names "$repository_name" >/dev/null 2>&1
}

clear_ecr_repository_images() {
  local repository_name="$1"
  CURRENT_OPERATION="Cleaning ECR repository '$repository_name'"

  # The platform stack cannot be deleted while its ECR repo still contains
  # tagged or untagged images, so clear the repo first when possible.
  if [[ -z "$repository_name" ]]; then
    echo "No repository name was found for this environment. Skipping ECR cleanup."
    return
  fi

  if ! ecr_repo_exists "$repository_name"; then
    echo "ECR repository '$repository_name' does not exist. Skipping cleanup."
    return
  fi

  step "Emptying ECR repository: $repository_name"

  while true; do
    local image_json
    image_json="$(aws_cli ecr list-images \
      --profile "$PROFILE" \
      --region "$REGION" \
      --repository-name "$repository_name" \
      --output json)"

    local image_ids=()
    case "$JSON_HELPER_KIND" in
      python|py)
        mapfile -t image_ids < <(run_python_helper "$image_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
for image in payload.get("imageIds", []):
    if image.get("imageTag"):
        print(f"imageTag={image['imageTag']}")
    elif image.get("imageDigest"):
        print(f"imageDigest={image['imageDigest']}")
PY
)
        ;;
      node)
        mapfile -t image_ids < <(node - "$image_json" <<'NODE'
const payload = JSON.parse(process.argv[2]);
for (const image of payload.imageIds || []) {
  if (image.imageTag) {
    console.log(`imageTag=${image.imageTag}`);
  } else if (image.imageDigest) {
    console.log(`imageDigest=${image.imageDigest}`);
  }
}
NODE
)
        ;;
      jq)
        mapfile -t image_ids < <(printf '%s' "$image_json" | jq -r '.imageIds[]? | if .imageTag then "imageTag=\(.imageTag)" else "imageDigest=\(.imageDigest)" end')
        ;;
      powershell)
        mapfile -t image_ids < <(
          {
            printf '%s\n' 'param([string]$JsonPayload)'
            printf '%s\n' '$payload = $JsonPayload | ConvertFrom-Json'
            printf '%s\n' 'foreach ($image in $payload.imageIds) {'
            printf '%s\n' '  if ($null -ne $image.imageTag -and [string]$image.imageTag -ne "") {'
            printf '%s\n' '    Write-Output ("imageTag=" + [string]$image.imageTag)'
            printf '%s\n' '  }'
            printf '%s\n' '  elseif ($null -ne $image.imageDigest -and [string]$image.imageDigest -ne "") {'
            printf '%s\n' '    Write-Output ("imageDigest=" + [string]$image.imageDigest)'
            printf '%s\n' '  }'
            printf '%s\n' '}'
          } | powershell.exe -NoProfile -Command - "$image_json"
        )
        ;;
      *)
        echo "Unsupported JSON helper kind: $JSON_HELPER_KIND" >&2
        return 1
        ;;
    esac

    if [[ ${#image_ids[@]} -eq 0 ]]; then
      echo "Repository '$repository_name' is already empty."
      break
    fi

    aws_cli ecr batch-delete-image \
      --profile "$PROFILE" \
      --region "$REGION" \
      --repository-name "$repository_name" \
      --image-ids "${image_ids[@]}"
  done
}

step "Checking prerequisites"
require_command aws

step "Verifying AWS credentials for profile '$PROFILE'"
CURRENT_OPERATION="Verifying AWS credentials"
aws_cli sts get-caller-identity --profile "$PROFILE" --region "$REGION" >/dev/null

# Delete in dependency order so later stacks are no longer referenced by
# earlier ones: service -> platform -> data -> networking.
delete_stack "$SERVICE_STACK_NAME"

if [[ "$SKIP_ECR_CLEANUP" != "true" ]]; then
  REPOSITORY_NAME="$(get_repository_name "$PLATFORM_PARAMETERS")"
  clear_ecr_repository_images "$REPOSITORY_NAME"
else
  echo "Skipping ECR cleanup by request."
fi

delete_stack "$PLATFORM_STACK_NAME"
delete_stack "$DATA_STACK_NAME"
delete_stack "$NETWORKING_STACK_NAME"

step "Checking for remaining stacks in environment '$ENVIRONMENT'"
CURRENT_OPERATION="Listing remaining stacks for environment '$ENVIRONMENT'"
aws_cli cloudformation list-stacks \
  --profile "$PROFILE" \
  --region "$REGION" \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED ROLLBACK_COMPLETE \
  --query "StackSummaries[?contains(StackName, '${ENVIRONMENT}')].[StackName,StackStatus]" \
  --output table

CURRENT_STACK_NAME=""
CURRENT_OPERATION=""

echo
echo "Teardown complete."
echo "Environment: $ENVIRONMENT"
echo "Elapsed time: $(elapsed_time_text)"
