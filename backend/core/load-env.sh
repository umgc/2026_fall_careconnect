#!/bin/bash
# ================================
# CareConnect Backend Environment Loader (Linux/macOS)
# ================================

set -e  # Exit on error

echo "Loading CareConnect environment variables..."

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "Error: .env file not found in current directory"
    echo "Please create a .env file based on the provided template"
    exit 1
fi

# Load environment variables from .env file
set -a  # Automatically export all variables
source .env
set +a  # Stop auto-exporting

echo "Environment variables loaded successfully!"
echo "Database: $JDBC_URI"

# Verify critical variables are set
required_vars=(
    "JDBC_URI"
    "DB_USER"
    "DB_PASSWORD"
    "SECURITY_JWT_SECRET"
    "FIREBASE_PROJECT_ID"
    "FIREBASE_SENDER_ID"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Warning: The following critical environment variables are not set:"
    printf '%s\n' "${missing_vars[@]}"
    echo "Please update your .env file with the required values"
fi

# Check optional environment variables and report which ones are using defaults
echo ""
echo "Optional environment variables (not set, using defaults from application-dev.properties):"
optional_vars=(
    "STRIPE_SECRET_KEY"
    "DEEPSEEK_API_KEY"
    "DEEPSEEK_OPENROUTER_API_KEY"
    "OPENAI_API_KEY"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "S3_BUCKET_NAME"
    "FITBIT_AUTHORIZATION_URI"
    "FITBIT_TOKEN_URI"
    "FITBIT_USERINFO_URI"
    "STRIPE_API_URL"
    "GOOGLE_CLIENT_ID"
    "GOOGLE_CLIENT_SECRET"
    "APPLE_SHARED_SECRET"
    "GOOGLE_ACCESS_TOKEN"
    "GOOGLE_SERVICE_ACCOUNT_FILE"
)

unset_count=0
for var in "${optional_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "  - $var"
        unset_count=$((unset_count + 1))  # not ((unset_count++)): that returns 1 when the count is 0, which set -e treats as a failure
    fi
done

if [ $unset_count -eq 0 ]; then
    echo "  (All optional variables are set)"
fi
echo ""

# Start the application if all critical vars are present
if [ ${#missing_vars[@]} -eq 0 ]; then
    echo "Starting CareConnect Backend..."
    exec "$@"
else
    echo "Please set the missing environment variables before starting the application"
    exit 1
fi
