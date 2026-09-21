# run-fast.ps1
# Fast local launch: build the executable jar only when sources changed, then run it with
# java -jar (skips the per-launch Maven recompile/dependency-resolution of spring-boot:run).
#
# Usage (from backend/core):
#   .\run-fast.ps1           # reuse jar if up to date, else build once, then run
#   .\run-fast.ps1 -Build    # force a rebuild first
#   .\run-fast.ps1 -Offline  # build in Maven offline mode (after ~/.m2 is populated)
param(
    [switch]$Build,
    [switch]$Offline
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# --- AWS creds for the SDK's DefaultCredentialsProvider (OS env, not .env) ---
Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
$env:AWS_PROFILE         = 'careconnect'
$env:AWS_REGION          = 'us-east-1'
$env:AWS_DEFAULT_REGION  = 'us-east-1'
$env:BEDROCK_REGION      = 'us-east-1'
$env:BEDROCK_MODEL_ID    = 'amazon.nova-pro-v1:0'

# Norton intercepts TLS: point the AWS CLI (not the JVM) at the combined CA bundle if present.
if (Test-Path "$env:USERPROFILE\.aws\careconnect-ca-bundle.pem") {
    $env:AWS_CA_BUNDLE = "$env:USERPROFILE\.aws\careconnect-ca-bundle.pem"
}
# The JVM (AWS SDK, Epic token exchange) needs the Norton root in a truststore.
$jvmOpts = @()
if (Test-Path "$env:USERPROFILE\.aws\careconnect-truststore.jks") {
    $jvmOpts += "-Djavax.net.ssl.trustStore=$env:USERPROFILE\.aws\careconnect-truststore.jks"
    $jvmOpts += "-Djavax.net.ssl.trustStorePassword=changeit"
}

# App run config (also present in .env, but set here so the jar/SDK see them regardless).
$env:SERVER_PORT             = '8081'
$env:SPRING_PROFILES_ACTIVE  = 'dev'
$env:CARECONNECT_AWS_ENABLED = 'true'
$env:CARECONNECT_AI_ENABLED  = 'true'

# --- Decide whether to (re)build ---
$jar = Join-Path $PSScriptRoot 'target\careconnect-backend-0.0.1-SNAPSHOT.jar'
$needBuild = $Build -or -not (Test-Path $jar)
if (-not $needBuild) {
    $jarTime = (Get-Item $jar).LastWriteTime
    $newest  = Get-ChildItem -Recurse -File -Path 'src\main', 'pom.xml' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest -and $newest.LastWriteTime -gt $jarTime) {
        Write-Host "Sources changed since last build ($($newest.Name)) - rebuilding..."
        $needBuild = $true
    }
}

if ($needBuild) {
    # -Pdocker is required: the default build activates the 'assembly-zip'/'assembly-zip-dev'
    # profiles (activeByDefault) which disable spring-boot repackage and produce a Lambda zip +
    # lib/ instead of a runnable jar. The 'docker' profile re-enables the executable fat jar
    # (jar + repackage) and skips the zip. Activating any -P profile also deactivates the two
    # activeByDefault ones, which is what we want.
    Write-Host "Building executable jar (-Pdocker; tests + dependency-check skipped)..."
    $mvnArgs = @('-q', '-Pdocker', '-DskipTests', '-Ddependency-check.skip=true', 'package')
    if ($Offline) { $mvnArgs = @('-o') + $mvnArgs }
    & .\mvnw.cmd @mvnArgs
    if ($LASTEXITCODE -ne 0) { throw "Maven build failed (exit $LASTEXITCODE)." }
} else {
    Write-Host "Reusing up-to-date jar: $jar"
}

Write-Host "Starting backend on :8081 (dev profile, Bedrock provider, model $env:BEDROCK_MODEL_ID)..."
Write-Host "Watch for the green 'BACKEND UP' banner below - that's when it's ready to use." -ForegroundColor DarkGray

# Mute the very verbose per-boot schema-patch logging so the readiness banner is not buried
# under ~150 'Schema patch applied' lines. Command-line only - does NOT touch the shared
# application-dev.properties (run-local-bedrock.ps1 still shows the full patch log).
$logQuiet = @(
    '-Dlogging.level.com.careconnect.config.SchemaPatchRunner=WARN',
    '-Dlogging.level.com.careconnect.config.SchemaPatchLedger=WARN'
)

# Stream the app's stdout; when Spring logs "Started ...Application in N seconds", print a clear
# banner so you know it's up (the API/Tomcat is already listening by this point). A few benign
# post-ready initializer lines (form sync, DataInitializer) may print just after - that's normal.
# Don't merge stderr (2>&1) here: in Windows PowerShell that wraps native stderr as ErrorRecords,
# which with $ErrorActionPreference='Stop' would abort mid-run. The readiness line is on stdout.
$ErrorActionPreference = 'Continue'
$ready = $false
& java @jvmOpts @logQuiet "-Dspring.profiles.active=dev" -jar $jar | ForEach-Object {
    $line = "$_"
    $line
    if (-not $ready -and $line -match 'Started \w+Application in ([\d.]+) seconds') {
        $ready = $true
        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Green
        Write-Host "  BACKEND UP  ->  http://localhost:8081"           -ForegroundColor Green
        Write-Host "  Swagger     ->  http://localhost:8081/swagger-ui.html" -ForegroundColor Green
        Write-Host "  Health      ->  http://localhost:8081/actuator/health" -ForegroundColor Green
        Write-Host "  Started in $($Matches[1])s. Press Ctrl+C to stop." -ForegroundColor Green
        Write-Host "==================================================" -ForegroundColor Green
        Write-Host ""
    }
}
