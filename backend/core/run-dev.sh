#!/bin/bash
# ================================
# CareConnect Backend Development Startup Script
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
echo "Starting CareConnect Backend in Development Mode..."
echo "=========================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker Desktop/daemon first."
    exit 1
fi

# Check if PostgreSQL container is running, start if not
echo "Checking PostgreSQL Docker container..."
if ! docker ps --format "table {{.Names}}" | grep -q "postgres_container"; then
    echo "PostgreSQL container not running. Starting it now..."

    # Check if docker-compose.yml exists
    if [ ! -f "pg_docker/docker-compose.yml" ]; then
        echo "Error: pg_docker/docker-compose.yml not found"
        echo "Please ensure the PostgreSQL Docker setup is in place"
        exit 1
    fi

    # Start PostgreSQL container
    cd pg_docker
    docker compose up -d postgres
    cd ..

    echo "Waiting for PostgreSQL to be ready..."
    sleep 10

    # Test PostgreSQL connection
    max_attempts=30
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if docker exec postgres_container pg_isready -U postgres > /dev/null 2>&1; then
            echo "PostgreSQL is ready!"
            break
        fi
        echo "Waiting for PostgreSQL... (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo "Error: PostgreSQL failed to start within expected time"
        exit 1
    fi
else
    echo "PostgreSQL container is already running"
fi

# Run Flyway migrations
#echo "Running database migrations..."
#./mvnw flyway:migrate -q   -Dflyway.url=jdbc:postgresql://localhost:5432/careconnect \
#                           -Dflyway.user=postgres \
#                           -Dflyway.password=changeme || {
#    echo "Warning: Flyway migrations failed. Continuing with application startup..."
#   echo "You may need to run migrations manually later."
#}

echo "----------------------------------------"
echo "Development Configuration:"
echo "- Database: PostgreSQL (Docker)"
echo "- Profile: dev"
echo "- DeepSeek AI: Real API (${DEEPSEEK_API_KEY:0:10}...)"
echo "- Other API Keys: Mocked"
echo "- Email: Console logging"
echo "- File Storage: Local"
echo "----------------------------------------"

echo "Starting Spring Boot application..."
export SPRING_PROFILES_ACTIVE=dev
export CARECONNECT_DATABASE_USE_AWS_CONFIG=false
export JAVA_TOOL_OPTIONS='-Dspring.mvc.log-request-details=true -Dlogging.level.org.hibernate.type.descriptor.sql=TRACE -Dlogging.level.org.hibernate.type.descriptor.sql.BasicBinder=TRACE -Dlogging.level.org.springframework.web=DEBUG'

# Norton Antivirus intercepts TLS on this machine (Web/Mail Shield), so outbound HTTPS from the
# JVM (Epic SMART-on-FHIR token exchange, AWS Bedrock SDK) fails PKIX cert validation with a
# ResourceAccessException unless the JVM trusts Norton's intercepting root. Point the JVM at a
# truststore that includes it when one is present (built once; see run-local-bedrock.ps1).
TRUSTSTORE="$HOME/.aws/careconnect-truststore.jks"
if [ -f "$TRUSTSTORE" ]; then
    # The Windows JVM needs a Windows-style path; a git-bash path like /c/Users/... would be
    # resolved by Java to C:\c\Users\... (nonexistent) and JSSE would silently fall back to an
    # EMPTY trust store, failing ALL outbound TLS. Convert with cygpath when available.
    if command -v cygpath >/dev/null 2>&1; then
        TRUSTSTORE_JVM="$(cygpath -m "$TRUSTSTORE")"
    else
        TRUSTSTORE_JVM="$TRUSTSTORE"
    fi
    echo "- TLS: using JVM truststore with intercepting root ($TRUSTSTORE_JVM)"
    export JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -Djavax.net.ssl.trustStore=$TRUSTSTORE_JVM -Djavax.net.ssl.trustStorePassword=changeit"
fi

./mvnw spring-boot:run -Dspring.profiles.active=dev

echo "Application stopped."
