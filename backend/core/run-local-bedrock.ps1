# run-local-bedrock.ps1
# Launch the CareConnect backend locally with AWS Bedrock (Nova Lite) enabled via an IAM user.
#
# Prerequisites (one-time): store your IAM user's access keys in the 'careconnect' profile:
#   aws configure --profile careconnect     # region us-east-1, output json
#
# Then from backend/core:  .\run-local-bedrock.ps1

$ErrorActionPreference = 'Stop'

# Clear any stray AWS key env vars — env creds OUTRANK the named profile in the default chain.
Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue

# AWS: use the IAM 'careconnect' profile + region for the SDK's DefaultCredentialsProvider.
$env:AWS_PROFILE      = 'careconnect'
$env:AWS_REGION       = 'us-east-1'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$env:BEDROCK_REGION   = 'us-east-1'
$env:BEDROCK_MODEL_ID = 'amazon.nova-lite-v1:0'

# Norton Antivirus intercepts TLS (Web/Mail Shield). Trust its root so the AWS CLI can verify
# AWS endpoints. NOTE: this env var is honored by the AWS CLI, NOT the Java SDK — for the
# backend itself, import the Norton root into the JDK truststore (see note below).
# Build once (only needed on machines where a proxy/AV intercepts TLS):
#   cat "$(aws --version | Out-Null; 'C:\Program Files\Amazon\AWSCLIV2\awscli\botocore\cacert.pem')" `
#       "C:\ProgramData\Norton\Antivirus\wscert.pem" > "$env:USERPROFILE\.aws\careconnect-ca-bundle.pem"
if (Test-Path "$env:USERPROFILE\.aws\careconnect-ca-bundle.pem") {
    $env:AWS_CA_BUNDLE = "$env:USERPROFILE\.aws\careconnect-ca-bundle.pem"
}

# App run config (dev profile, port 8081, DB on 5433) + AWS/AI enabled.
$env:SERVER_PORT             = '8081'
$env:SPRING_PROFILES_ACTIVE  = 'dev'
$env:JDBC_URI                = 'jdbc:postgresql://localhost:5433/careconnect'
$env:DB_USER                 = 'postgres'
$env:DB_PASSWORD             = 'changeme'
$env:CARECONNECT_AWS_ENABLED = 'true'
$env:CARECONNECT_AI_ENABLED  = 'true'

# Fail fast if the profile credentials are missing/invalid, with a clear hint.
try {
    aws sts get-caller-identity --profile careconnect --output text | Out-Null
} catch {
    Write-Warning "AWS credentials not working for profile 'careconnect'. Run:  aws configure --profile careconnect"
    throw
}

# Norton TLS: the AWS Java SDK uses the JDK truststore (it ignores AWS_CA_BUNDLE). Point the JVM
# at a truststore that includes the intercepting root — built once (no admin) from the JDK cacerts:
#   Copy-Item "$env:JAVA_HOME\lib\security\cacerts" "$env:USERPROFILE\.aws\careconnect-truststore.jks"
#   keytool -importcert -alias norton-ssl-root -noprompt -storepass changeit `
#     -file "C:\ProgramData\Norton\Antivirus\wscert.pem" `
#     -keystore "$env:USERPROFILE\.aws\careconnect-truststore.jks"
# Only needed where a proxy/AV intercepts TLS; skipped automatically otherwise.
if (Test-Path "$env:USERPROFILE\.aws\careconnect-truststore.jks") {
    $env:JAVA_TOOL_OPTIONS = "-Djavax.net.ssl.trustStore=$env:USERPROFILE\.aws\careconnect-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"
}

Write-Host "Starting backend on :8081 with Bedrock provider (model amazon.nova-lite-v1:0, region us-east-1, profile careconnect)..."
.\mvnw.cmd spring-boot:run
