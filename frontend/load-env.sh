#!/bin/bash
# ================================
# CareConnect Frontend Environment Loader (Linux/macOS)
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

# Default sentiment mode when not provided
CC_SENTIMENT_MODE="${CC_SENTIMENT_MODE:-balanced}"
export CC_SENTIMENT_MODE

# Verify critical variables are set
required_vars=(
"CC_BASE_URL_WEB"
"CC_BASE_URL_ANDROID"
"CC_BASE_URL_OTHER"
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

# Start the application if all critical vars are present
if [ ${#missing_vars[@]} -eq 0 ]; then
    if [ "$1" = "flutter" ]; then
        echo "Using sentiment mode: $CC_SENTIMENT_MODE"
        exec "$@" --dart-define=CARECONNECT_SENTIMENT_MODE="$CC_SENTIMENT_MODE"
    else
        exec "$@"
    fi
else
    echo "Please set the missing environment variables before starting the application"
    exit 1
fi
