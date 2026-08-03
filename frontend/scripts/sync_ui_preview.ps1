# Sync React Care Circle preview into Flutter web/ui-preview.
# Run from anywhere; resolves paths relative to this script.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendDir = Resolve-Path (Join-Path $ScriptDir "..")
$RepoRoot = Resolve-Path (Join-Path $FrontendDir "..")
$MobileApp = Join-Path $RepoRoot "ui-integration\mobile-app"
$Dest = Join-Path $FrontendDir "web\ui-preview"

Write-Host "Building React UI preview from $MobileApp"
Push-Location $MobileApp
try {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
} finally {
  Pop-Location
}

$Dist = Join-Path $MobileApp "dist"
if (-not (Test-Path $Dist)) {
  throw "Build output missing at $Dist"
}

if (Test-Path $Dest) {
  Remove-Item -Recurse -Force $Dest
}
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Copy-Item -Path (Join-Path $Dist "*") -Destination $Dest -Recurse -Force

Set-Content -Path (Join-Path $Dest "README.txt") -Value @"
Generated files — do not edit by hand.
Built from ui-integration/mobile-app via frontend/scripts/sync_ui_preview.ps1 (or sync_ui_preview.sh).
Amplify also rebuilds these during frontend/amplify.yml before flutter build web.
"@

Write-Host "Synced UI preview to $Dest"
