#!/usr/bin/env bash

set -euo pipefail

START_TIME="$(date +%s)"

# Track the active stack/operation so the ERR trap can print useful context.
ENVIRONMENT="dev"
PROFILE=""
REGION="us-east-1"
IMAGE_TAG=""
RUN_TESTS="false"
CURRENT_STACK_NAME=""
CURRENT_OPERATION=""
ORIGINAL_AWS_PROFILE="${AWS_PROFILE-}"

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
    -t|--image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --run-tests)
      RUN_TESTS="true"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./cdeploy_app_only.sh [options]

Builds the backend, pushes the Docker image to ECR, and deploys the ECS
service stack with API Gateway HTTP API, VPC Link, and Cloud Map integration.

Options:
  -e, --environment <name>   Environment name: dev, cfdemo, staging, prod
  -p, --profile <profile>    Optional AWS CLI profile for local use
  -r, --region <region>      AWS region (default: us-east-1)
  -t, --image-tag <tag>      Docker/ECR image tag (default: env + git SHA or timestamp)
      --run-tests            Run Maven tests during package build
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

if [[ -n "$PROFILE" ]]; then
  # Local developers can still target a named AWS profile. In GitHub Actions we
  # leave this empty so the script uses the temporary credentials from OIDC.
  export AWS_PROFILE="$PROFILE"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
PARAMETER_DIR="$SCRIPT_DIR/parameters"
BACKEND_DIR="$REPO_ROOT/backend/core"

# App-only deploys should use unique tags so every pipeline run can be traced
# back to a specific commit or build.
if [[ -z "$IMAGE_TAG" ]]; then
  if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    IMAGE_TAG="${ENVIRONMENT}-$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  else
    IMAGE_TAG="${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)"
  fi
fi

IN_MSYS="false"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    IN_MSYS="true"
    ;;
esac

STACK_PREFIX="careconnect"
PLATFORM_STACK_NAME="${STACK_PREFIX}-platform-${ENVIRONMENT}"
SERVICE_STACK_NAME="${STACK_PREFIX}-service-${ENVIRONMENT}"

SERVICE_TEMPLATE="$TEMPLATE_DIR/04-service.yaml"
SERVICE_PARAMETERS="$PARAMETER_DIR/${ENVIRONMENT}-service.json"

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
  echo "App-only deployment failed." >&2
  echo "Exit code: $exit_code (line $line_number)" >&2
  echo "Elapsed time: $(elapsed_time_text)" >&2

  if [[ -n "$CURRENT_OPERATION" ]]; then
    echo "Last operation: $CURRENT_OPERATION" >&2
  fi

  if [[ -n "$CURRENT_STACK_NAME" ]]; then
    echo >&2
    echo "CloudFormation troubleshooting for stack '$CURRENT_STACK_NAME':" >&2
    write_stack_failure_details "$CURRENT_STACK_NAME" >&2 || true
    echo >&2
    echo "Manual command:" >&2
    if [[ -n "$PROFILE" ]]; then
      echo "AWS_PROFILE=\"$PROFILE\" aws cloudformation describe-stack-events --region \"$REGION\" --stack-name \"$CURRENT_STACK_NAME\" --query \"StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]\" --output table" >&2
    else
      echo "aws cloudformation describe-stack-events --region \"$REGION\" --stack-name \"$CURRENT_STACK_NAME\" --query \"StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]\" --output table" >&2
    fi
  fi

  exit "$exit_code"
}

cleanup() {
  if [[ -n "$PROFILE" ]]; then
    if [[ -n "$ORIGINAL_AWS_PROFILE" ]]; then
      export AWS_PROFILE="$ORIGINAL_AWS_PROFILE"
    else
      unset AWS_PROFILE
    fi
  fi
}

trap 'on_error $? $LINENO' ERR
trap cleanup EXIT

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Required command not found in PATH: $name" >&2
    exit 1
  fi
}

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Required path not found: $path" >&2
    exit 1
  fi
}

to_aws_path() {
  local path="$1"
  if [[ "$IN_MSYS" == "true" ]] && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
}

aws_cli() {
  if [[ "$IN_MSYS" == "true" ]]; then
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' aws "$@"
  else
    aws "$@"
  fi
}

stack_exists() {
  local stack_name="$1"
  if aws_cli cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$stack_name" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

get_stack_status() {
  local stack_name="$1"
  aws_cli cloudformation describe-stacks \
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
    --region "$REGION" \
    --stack-name "$stack_name" \
    --query "StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]" \
    --output table || true
}

JSON_HELPER=""
JSON_HELPER_KIND=""

command_runs() {
  local name="$1"
  shift

  if ! command -v "$name" >/dev/null 2>&1; then
    return 1
  fi

  "$name" "$@" >/dev/null 2>&1
}

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

  case "$JSON_HELPER_KIND" in
    py)
      py -3 - "$parameter_file" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
for entry in data:
    print(f"{entry['ParameterKey']}={entry['ParameterValue']}")
PY
      ;;
    python)
      "$JSON_HELPER" - "$parameter_file" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
for entry in data:
    print(f"{entry['ParameterKey']}={entry['ParameterValue']}")
PY
      ;;
    node)
      node - "$parameter_file" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
for (const entry of data) {
  console.log(`${entry.ParameterKey}=${entry.ParameterValue}`);
}
NODE
      ;;
    jq)
      jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$parameter_file"
      ;;
    powershell)
      printf '%s\n' "\$data = Get-Content -LiteralPath '$parameter_file' -Raw | ConvertFrom-Json; foreach (\$entry in \$data) { Write-Output (\"\$($entry.ParameterKey)=\$($entry.ParameterValue)\") }" | powershell.exe -NoProfile -Command -
      ;;
    *)
      echo "Unsupported JSON helper kind: $JSON_HELPER_KIND" >&2
      exit 1
      ;;
  esac
}

build_parameter_overrides() {
  local parameter_file="$1"
  shift || true

  # Convert the checked-in JSON parameter file into the Key=Value format that
  # `aws cloudformation deploy` expects. Extra overrides are appended last so
  # the CLI receives the final image URI from the current build.
  local -a overrides=()
  mapfile -t overrides < <(run_python_helper "$parameter_file")

  local extra
  for extra in "$@"; do
    local key="${extra%%=*}"
    local replaced="false"
    local i
    for i in "${!overrides[@]}"; do
      if [[ "${overrides[$i]%%=*}" == "$key" ]]; then
        overrides[$i]="$extra"
        replaced="true"
      fi
    done
    if [[ "$replaced" != "true" ]]; then
      overrides+=("$extra")
    fi
  done

  printf '%s\n' "${overrides[@]}"
}

deploy_stack() {
  local stack_name="$1"
  local template_path="$2"
  local parameter_file="$3"
  shift 3

  CURRENT_STACK_NAME="$stack_name"
  local stack_status
  stack_status="$(get_stack_status "$stack_name" | tr -d '\r')"
  if [[ "$stack_status" == "ROLLBACK_COMPLETE" ]]; then
    echo "Stack '$stack_name' is in ROLLBACK_COMPLETE. Deleting it before retrying deployment..."
    CURRENT_OPERATION="Deleting rollback-complete stack '$stack_name'"
    aws_cli cloudformation delete-stack \
      --region "$REGION" \
      --stack-name "$stack_name"

    aws_cli cloudformation wait stack-delete-complete \
      --region "$REGION" \
      --stack-name "$stack_name"
  fi

  local operation
  if stack_exists "$stack_name"; then
    operation="Updating"
  else
    operation="Creating"
  fi

  CURRENT_OPERATION="${operation} stack '$stack_name'"
  echo "${operation} stack '$stack_name'..."

  local -a parameter_overrides
  mapfile -t parameter_overrides < <(build_parameter_overrides "$parameter_file" "$@")
  local aws_template_path
  aws_template_path="$(to_aws_path "$template_path")"

  if ! aws_cli cloudformation deploy \
    --region "$REGION" \
    --stack-name "$stack_name" \
    --template-file "$aws_template_path" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides "${parameter_overrides[@]}"; then
    write_stack_failure_details "$stack_name"
    exit 1
  fi

  local final_status
  final_status="$(get_stack_status "$stack_name" | tr -d '\r')"
  if [[ -n "$final_status" && "$final_status" != "None" ]]; then
    echo "Stack '$stack_name' is now $final_status."
  fi
}

get_stack_output() {
  local stack_name="$1"
  local output_key="$2"

  aws_cli cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$stack_name" \
    --query "Stacks[0].Outputs[?OutputKey=='${output_key}'].OutputValue" \
    --output text
}

step "Checking prerequisites"
for cmd in aws docker java; do
  require_command "$cmd"
done

require_path "$SERVICE_TEMPLATE"
require_path "$SERVICE_PARAMETERS"
require_path "$BACKEND_DIR"
require_path "$BACKEND_DIR/mvnw"

step "Verifying AWS credentials"
CURRENT_OPERATION="Verifying AWS credentials"
aws_cli sts get-caller-identity --region "$REGION" >/dev/null

if ! stack_exists "$PLATFORM_STACK_NAME"; then
  echo "Platform stack '$PLATFORM_STACK_NAME' does not exist. Run the full deploy first so the ECR repository and ECS cluster are available." >&2
  exit 1
fi

step "Reading ECR repository URI"
CURRENT_OPERATION="Reading ECR repository URI"
REPOSITORY_URI="$(get_stack_output "$PLATFORM_STACK_NAME" "EcrRepositoryUri" | tr -d '\r')"
if [[ -z "$REPOSITORY_URI" || "$REPOSITORY_URI" == "None" ]]; then
  echo "Platform stack '$PLATFORM_STACK_NAME' did not return EcrRepositoryUri." >&2
  exit 1
fi

REPOSITORY_NAME="${REPOSITORY_URI#*/}"
IMAGE_URI="${REPOSITORY_URI}:${IMAGE_TAG}"
LOCAL_IMAGE_NAME="careconnect-backend-local:${IMAGE_TAG}"
REGISTRY_HOST="${REPOSITORY_URI%%/*}"

step "Building backend jar"
pushd "$BACKEND_DIR" >/dev/null
CURRENT_OPERATION="Building backend jar"
# Use batch mode and suppress Maven transfer-progress spam so CI logs stay
# readable and it is easier to tell whether the build is really moving.
MAVEN_ARGS=(-B -ntp clean package -Pdocker)
if [[ "$RUN_TESTS" != "true" ]]; then
  MAVEN_ARGS+=(-DskipTests)
fi
./mvnw "${MAVEN_ARGS[@]}"

step "Logging into ECR"
CURRENT_OPERATION="Logging into ECR"
aws_cli ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY_HOST"

step "Building Docker image"
CURRENT_OPERATION="Building Docker image"
docker build -t "$LOCAL_IMAGE_NAME" .

step "Tagging and pushing Docker image to ECR"
CURRENT_OPERATION="Pushing Docker image to ECR"
docker tag "$LOCAL_IMAGE_NAME" "$IMAGE_URI"
docker push "$IMAGE_URI"
popd >/dev/null

step "Deploying service stack: $SERVICE_STACK_NAME"
deploy_stack "$SERVICE_STACK_NAME" "$SERVICE_TEMPLATE" "$SERVICE_PARAMETERS" "BackendImageUri=${IMAGE_URI}"

step "Reading final API endpoint"
CURRENT_OPERATION="Reading final API endpoint"
API_ENDPOINT="$(get_stack_output "$SERVICE_STACK_NAME" "ApiEndpoint" | tr -d '\r')"
CURRENT_STACK_NAME=""
CURRENT_OPERATION=""

echo
echo "App-only deployment complete."
echo "Environment:   $ENVIRONMENT"
echo "Repository:    $REPOSITORY_NAME"
echo "Image URI:     $IMAGE_URI"
echo "API Endpoint:  $API_ENDPOINT"
echo "Health check:  ${API_ENDPOINT}/v1/api/test/health"
echo "Elapsed time:  $(elapsed_time_text)"
