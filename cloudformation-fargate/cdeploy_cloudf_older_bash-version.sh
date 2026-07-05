#!/usr/bin/env bash

set -euo pipefail

START_TIME="$(date +%s)"

# Track the active stack/operation so the ERR trap can print useful context.
ENVIRONMENT="dev"
PROFILE="careconnect-sso"
REGION="us-east-1"
IMAGE_TAG=""
RUN_TESTS="false"
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
Usage: ./cdeploy_cloudformation.sh [options]

Options:
  -e, --environment <name>   Environment name: dev, cfdemo, staging, prod
  -p, --profile <profile>    AWS CLI profile (default: careconnect-sso)
  -r, --region <region>      AWS region (default: us-east-1)
  -t, --image-tag <tag>      Docker/ECR image tag (default: same as environment)
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

if [[ -z "$IMAGE_TAG" ]]; then
  # Default the Docker tag to the environment name so dev/cfdemo stay separate.
  IMAGE_TAG="$ENVIRONMENT"
fi

# Resolve repository-relative paths so the script works from any starting folder.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
PARAMETER_DIR="$SCRIPT_DIR/parameters"
BACKEND_DIR="$REPO_ROOT/backend/core"

IN_MSYS="false"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    IN_MSYS="true"
    ;;
esac

STACK_PREFIX="careconnect"
NETWORKING_STACK_NAME="${STACK_PREFIX}-networking-${ENVIRONMENT}"
DATA_STACK_NAME="${STACK_PREFIX}-data-${ENVIRONMENT}"
PLATFORM_STACK_NAME="${STACK_PREFIX}-platform-${ENVIRONMENT}"
SERVICE_STACK_NAME="${STACK_PREFIX}-service-${ENVIRONMENT}"

NETWORKING_TEMPLATE="$TEMPLATE_DIR/01-networking.yaml"
DATA_TEMPLATE="$TEMPLATE_DIR/02-data.yaml"
PLATFORM_TEMPLATE="$TEMPLATE_DIR/03-platform.yaml"
SERVICE_TEMPLATE="$TEMPLATE_DIR/04-service.yaml"

NETWORKING_PARAMETERS="$PARAMETER_DIR/${ENVIRONMENT}-networking.json"
DATA_PARAMETERS="$PARAMETER_DIR/${ENVIRONMENT}-data.json"
PLATFORM_PARAMETERS="$PARAMETER_DIR/${ENVIRONMENT}-platform.json"
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
  echo "Deployment failed." >&2
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
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name" >/dev/null 2>&1; then
    return 0
  fi

  return 1
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

build_parameter_overrides() {
  local parameter_file="$1"
  shift || true

  case "$JSON_HELPER_KIND" in
    python|py)
      run_python_helper "$parameter_file" "$@" <<'PY'
import json
import sys

parameter_file = sys.argv[1]
overrides = {}
for arg in sys.argv[2:]:
    key, value = arg.split("=", 1)
    overrides[key] = value

with open(parameter_file, "r", encoding="utf-8") as fh:
    entries = json.load(fh)

for entry in entries:
    key = str(entry["ParameterKey"])
    value = str(entry["ParameterValue"])
    if key in overrides:
        value = overrides[key]
    print(f"{key}={value}")
PY
      ;;
    node)
      node - "$parameter_file" "$@" <<'NODE'
const fs = require("fs");

const parameterFile = process.argv[2];
const overrideArgs = process.argv.slice(3);
const overrides = {};

for (const arg of overrideArgs) {
  const idx = arg.indexOf("=");
  const key = arg.slice(0, idx);
  const value = arg.slice(idx + 1);
  overrides[key] = value;
}

const entries = JSON.parse(fs.readFileSync(parameterFile, "utf8"));
for (const entry of entries) {
  const key = String(entry.ParameterKey);
  const value = Object.prototype.hasOwnProperty.call(overrides, key)
    ? String(overrides[key])
    : String(entry.ParameterValue);
  console.log(`${key}=${value}`);
}
NODE
      ;;
    jq)
      local jq_overrides='{}'
      local override
      for override in "$@"; do
        local key="${override%%=*}"
        local value="${override#*=}"
        jq_overrides="$(printf '%s' "$jq_overrides" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')"
      done

      jq -r --argjson overrides "$jq_overrides" '
        .[] | "\(.ParameterKey)=\(($overrides[.ParameterKey] // .ParameterValue) | tostring)"
      ' "$parameter_file"
      ;;
    powershell)
      {
        printf '%s\n' 'param([string]$ParameterFile, [string[]]$Overrides)'
        printf '%s\n' '$map = @{}'
        printf '%s\n' 'foreach ($item in $Overrides) {'
        printf '%s\n' '  $parts = $item -split "=", 2'
        printf '%s\n' '  $map[$parts[0]] = $parts[1]'
        printf '%s\n' '}'
        printf '%s\n' '$entries = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json'
        printf '%s\n' 'foreach ($entry in $entries) {'
        printf '%s\n' '  $key = [string]$entry.ParameterKey'
        printf '%s\n' '  $value = if ($map.ContainsKey($key)) { [string]$map[$key] } else { [string]$entry.ParameterValue }'
        printf '%s\n' '  Write-Output ($key + "=" + $value)'
        printf '%s\n' '}'
      } | powershell.exe -NoProfile -Command - "$parameter_file" "$@"
      ;;
    *)
      echo "Unsupported JSON helper kind: $JSON_HELPER_KIND" >&2
      return 1
      ;;
  esac
}

deploy_stack() {
  local stack_name="$1"
  local template_path="$2"
  local parameter_file="$3"
  shift 3 || true

  CURRENT_STACK_NAME="$stack_name"
  
  # --- FIX: Compatibility for Mac Bash 3.2 ---
  local parameter_overrides=()
  while IFS= read -r line; do
    parameter_overrides+=("$line")
  done < <(build_parameter_overrides "$parameter_file" "$@")
  # ------------------------------------------

  local stack_status=""
  if stack_exists "$stack_name"; then
    stack_status="$(get_stack_status "$stack_name" | tr -d '\r')"
  fi

  if [[ "$stack_status" == "ROLLBACK_COMPLETE" ]]; then
    echo "Stack '$stack_name' is in ROLLBACK_COMPLETE. Deleting it before retrying deployment..."
    aws_cli cloudformation delete-stack \
      --profile "$PROFILE" \
      --region "$REGION" \
      --stack-name "$stack_name"
    aws_cli cloudformation wait stack-delete-complete \
      --profile "$PROFILE" \
      --region "$REGION" \
      --stack-name "$stack_name"
    stack_status=""
  fi

  local operation="Creating"
  if [[ -n "$stack_status" ]]; then
    operation="Updating"
  fi

  CURRENT_OPERATION="$operation stack '$stack_name'"
  echo "$operation stack '$stack_name'..."

  local aws_template_path
  aws_template_path="$(to_aws_path "$template_path")"

  if ! aws_cli cloudformation deploy \
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name" \
    --template-file "$aws_template_path" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides "${parameter_overrides[@]}"; then
    write_stack_failure_details "$stack_name"
    return 1
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
    --profile "$PROFILE" \
    --region "$REGION" \
    --stack-name "$stack_name" \
    --query "Stacks[0].Outputs[?OutputKey=='${output_key}'].OutputValue" \
    --output text
}

assert_no_placeholders() {
  local parameter_file="$1"
  if grep -q 'REPLACE_ME' "$parameter_file"; then
    echo "Parameter file '$parameter_file' still contains placeholder values." >&2
    exit 1
  fi
}

step "Checking prerequisites"
for cmd in aws docker git java; do
  require_command "$cmd"
done

require_path "$NETWORKING_TEMPLATE"
require_path "$DATA_TEMPLATE"
require_path "$PLATFORM_TEMPLATE"
require_path "$SERVICE_TEMPLATE"
require_path "$NETWORKING_PARAMETERS"
require_path "$DATA_PARAMETERS"
require_path "$PLATFORM_PARAMETERS"
require_path "$SERVICE_PARAMETERS"
require_path "$BACKEND_DIR"
require_path "$BACKEND_DIR/mvnw"

assert_no_placeholders "$DATA_PARAMETERS"

step "Verifying AWS credentials for profile '$PROFILE'"
CURRENT_OPERATION="Verifying AWS credentials"
aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" >/dev/null

step "Deploying networking stack: $NETWORKING_STACK_NAME"
deploy_stack "$NETWORKING_STACK_NAME" "$NETWORKING_TEMPLATE" "$NETWORKING_PARAMETERS"

step "Deploying data stack: $DATA_STACK_NAME"
deploy_stack "$DATA_STACK_NAME" "$DATA_TEMPLATE" "$DATA_PARAMETERS"

step "Deploying platform stack: $PLATFORM_STACK_NAME"
deploy_stack "$PLATFORM_STACK_NAME" "$PLATFORM_TEMPLATE" "$PLATFORM_PARAMETERS"

step "Reading ECR repository URI"
CURRENT_OPERATION="Reading ECR repository URI"
REPOSITORY_URI="$(get_stack_output "$PLATFORM_STACK_NAME" "EcrRepositoryUri" | tr -d '\r')"
if [[ -z "$REPOSITORY_URI" || "$REPOSITORY_URI" == "None" ]]; then
  echo "Platform stack did not return EcrRepositoryUri." >&2
  exit 1
fi

REPOSITORY_NAME="${REPOSITORY_URI#*/}"
IMAGE_URI="${REPOSITORY_URI}:${IMAGE_TAG}"
LOCAL_IMAGE_NAME="careconnect-backend-local:${IMAGE_TAG}"
REGISTRY_HOST="${REPOSITORY_URI%%/*}"

step "Building backend jar"
pushd "$BACKEND_DIR" >/dev/null
CURRENT_OPERATION="Building backend jar"
MAVEN_ARGS=(clean package -Pdocker)
if [[ "$RUN_TESTS" != "true" ]]; then
  MAVEN_ARGS+=(-DskipTests)
fi
./mvnw "${MAVEN_ARGS[@]}"

step "Logging into ECR"
CURRENT_OPERATION="Logging into ECR"
aws_cli ecr get-login-password --profile "$PROFILE" --region "$REGION" \
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
echo "Deployment complete."
echo "Environment:   $ENVIRONMENT"
echo "Repository:    $REPOSITORY_NAME"
echo "Image URI:     $IMAGE_URI"
echo "API Endpoint:  $API_ENDPOINT"
echo "Health check:  ${API_ENDPOINT}/v1/api/test/health"
echo "Elapsed time:  $(elapsed_time_text)"