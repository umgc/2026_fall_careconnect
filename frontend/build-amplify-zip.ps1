# Builds the Flutter web app and zips build/web's *contents* (not the folder
# itself) into manual-amplify.zip, one level above the git repo — matching
# the existing manual Amplify drag-and-drop upload flow documented in
# frontend/README.md and cloudformation-fargate/DEPLOY_2026_SUMMER.md §5.
#
# All three -BackendUrl/-AppDomain/-AppPort values are optional. Leave them
# blank to reproduce the plain `flutter build web` documented in
# frontend/README.md (falls back to http://localhost:8080 at runtime); set
# -BackendUrl to point the build at a real deployed backend instead.

param(
    [string]$BackendUrl,
    [string]$AppDomain,
    [string]$AppPort,
    [string]$OutputZip,

    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Help) {
    @"
Usage: .\build-amplify-zip.ps1 [options]

Builds frontend/build/web and zips its contents for manual upload to AWS
Amplify (Amplify console -> app -> branch -> Deploy updates -> drag and drop).

Options:
  -BackendUrl <url>    --dart-define=BACKEND_URL (blank: falls back to
                         http://localhost:8080 at runtime)
  -AppDomain <host>    --dart-define=APP_DOMAIN (hostname only, no https://)
                         — needed alongside -BackendUrl for a real deployed
                         backend
  -AppPort <port>      --dart-define=APP_PORT (typically 443 for a real
                         deployed backend)
  -OutputZip <path>    Zip output path (default: ..\manual-amplify.zip, i.e.
                         one level above the git repo, matching the existing
                         manual deploy convention)
  -Help, -h            Show this help text
"@ | Write-Host
    exit 0
}

if ($BackendUrl -and $BackendUrl -notmatch '^https?://') {
    Write-Warning "-BackendUrl '$BackendUrl' has no http:// or https:// scheme."
    Write-Warning "Without one, the compiled app treats it as a relative path and resolves API calls against whatever domain hosts the built app, not the intended backend."
    $reply = Read-Host "Add https:// automatically? [Y/n]"
    if (-not $reply -or $reply -match '^[Yy]') {
        $BackendUrl = "https://$BackendUrl"
        Write-Host "Using: $BackendUrl"
    }
    else {
        Write-Warning "Proceeding with '$BackendUrl' as-is."
    }
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot

if (-not $OutputZip) {
    $OutputZip = Join-Path (Split-Path -Parent $RepoRoot) "manual-amplify.zip"
}

Push-Location $ScriptRoot
try {
    $buildArgs = @("build", "web", "--release", "--base-href", "/")
    if ($BackendUrl) {
        $buildArgs += "--dart-define=BACKEND_URL=$BackendUrl"
    }
    if ($AppDomain) {
        $buildArgs += "--dart-define=APP_DOMAIN=$AppDomain"
    }
    if ($AppPort) {
        $buildArgs += "--dart-define=APP_PORT=$AppPort"
    }

    Write-Host "Running: flutter $($buildArgs -join ' ')"
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build web failed with exit code $LASTEXITCODE"
    }

    if (Test-Path -LiteralPath $OutputZip) {
        Remove-Item -LiteralPath $OutputZip -Force
    }

    Push-Location (Join-Path $ScriptRoot "build\web")
    try {
        Compress-Archive -Path (Join-Path (Get-Location) "*") -DestinationPath $OutputZip
    }
    finally {
        Pop-Location
    }

    Write-Host "Wrote $OutputZip"
    Write-Host "Upload it: Amplify console -> your app -> branch -> Deploy updates -> drag and drop"
}
finally {
    Pop-Location
}
