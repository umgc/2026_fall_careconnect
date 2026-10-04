# Builds an isolated, online-only desktop preview using the installed Flutter SDK.
[CmdletBinding()]
param(
    [string]$BackendUrl = 'http://localhost:8080',
    [string]$FlutterPath = '',
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $repoRoot 'frontend'
$previewRoot = Join-Path $repoRoot 'tmp/windows-online'

if (!$FlutterPath) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $FlutterPath = $flutterCommand.Source
    } else {
        $FlutterPath = Join-Path $env:USERPROFILE 'flutter/bin/flutter.bat'
    }
}
if (!(Test-Path -LiteralPath $FlutterPath)) {
    throw 'Flutter was not found. Supply -FlutterPath with the path to flutter.bat.'
}

# Resolve packages in the original frontend only if no package inventory exists.
$packageConfig = Join-Path $sourceRoot '.dart_tool/package_config.json'
if (!(Test-Path -LiteralPath $packageConfig)) {
    Push-Location $sourceRoot
    try {
        & $FlutterPath pub get --offline
        if ($LASTEXITCODE) { throw 'Could not resolve cached frontend dependencies.' }
    } finally { Pop-Location }
}

New-Item -ItemType Directory -Force -Path $previewRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRoot 'lib') -Destination $previewRoot -Recurse -Force
foreach ($relativePath in @('.env.example', 'l10n.yaml', 'pubspec.lock')) {
    $sourcePath = Join-Path $sourceRoot $relativePath
    if (Test-Path -LiteralPath $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination $previewRoot -Force
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $previewRoot 'windows/flutter') | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRoot 'windows/runner') -Destination (Join-Path $previewRoot 'windows') -Recurse -Force
foreach ($relativePath in @('windows/CMakeLists.txt', 'windows/flutter/CMakeLists.txt')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $relativePath) -Destination (Join-Path $previewRoot $relativePath) -Force
}
# A previous failed configure can cache CMake's Program Files install prefix.
# Always bundle this preview beside its executable, including on retries.
$cmakePath = Join-Path $previewRoot 'windows/CMakeLists.txt'
$cmake = Get-Content $cmakePath -Raw
$cmake = $cmake -replace '(?s)if\(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT\)\s*(set\(CMAKE_INSTALL_PREFIX[^\r\n]*\))\s*endif\(\)', '$1'
Set-Content -LiteralPath $cmakePath -Value $cmake -Encoding utf8
# Share large model assets without duplicating them.
$assetsPath = Join-Path $previewRoot 'assets'
if (!(Test-Path -LiteralPath $assetsPath)) {
    New-Item -ItemType Junction -Path $assetsPath -Target (Join-Path $sourceRoot 'assets') | Out-Null
}

$manifest = Get-Content (Join-Path $sourceRoot 'pubspec.yaml') -Raw
$manifest = $manifest -replace '(?m)^  (sqlite3|sqlcipher_flutter_libs):[^\r\n]*\r?\n', ''

# Keep Dart APIs available, but omit the native integrations requiring NuGet.
# These copies are disposable; the global pub cache is never modified.
$packages = (Get-Content $packageConfig -Raw | ConvertFrom-Json).packages
$overrides = ''
foreach ($name in @('flutter_tts', 'geolocator', 'geolocator_windows', 'permission_handler', 'permission_handler_windows')) {
    $package = $packages | Where-Object name -eq $name
    if (!$package) { throw "Package $name is missing from the frontend package inventory." }
    $packageRoot = ([uri]$package.rootUri).LocalPath
    $localRoot = Join-Path $previewRoot "preview_plugins/$name"
    New-Item -ItemType Directory -Force -Path $localRoot | Out-Null
    foreach ($relativePath in @('lib', 'LICENSE')) {
        $sourcePath = Join-Path $packageRoot $relativePath
        if (Test-Path -LiteralPath $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination $localRoot -Recurse -Force
        }
    }
    $packageManifest = Get-Content (Join-Path $packageRoot 'pubspec.yaml') -Raw
    $packageManifest = $packageManifest -replace '(?ms)^flutter:\r?\n.*?(?=^[^\s#]|\z)', ''
    Set-Content -LiteralPath (Join-Path $localRoot 'pubspec.yaml') -Value $packageManifest -Encoding utf8
    $overrides += "`n  ${name}:`n    path: preview_plugins/$name"
}
$manifest = $manifest -replace 'dependency_overrides:', "dependency_overrides:$overrides"
# Secure storage uses ATL only for string conversions. Preserve its credential
# and encryption implementation while replacing those helpers with Win32 APIs.
$storagePackage = $packages | Where-Object name -eq 'flutter_secure_storage_windows'
$storageSource = ([uri]$storagePackage.rootUri).LocalPath
$storageTarget = Join-Path $previewRoot 'preview_plugins/flutter_secure_storage_windows'
New-Item -ItemType Directory -Force -Path $storageTarget | Out-Null
foreach ($relativePath in @('lib', 'windows', 'LICENSE', 'pubspec.yaml')) {
    Copy-Item -LiteralPath (Join-Path $storageSource $relativePath) -Destination $storageTarget -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows-string-conversions.h') -Destination (Join-Path $storageTarget 'windows') -Force
$storageCppPath = Join-Path $storageTarget 'windows/flutter_secure_storage_windows_plugin.cpp'
$storageCpp = Get-Content $storageCppPath -Raw
$storageCpp = $storageCpp.Replace('#include <atlstr.h>', '#include "windows-string-conversions.h"')
$storageCpp = $storageCpp -replace '(?:const )?CA2W (\w+)\((.*)\);', 'auto $1 = WidenWindowsString($2);'
$storageCpp = $storageCpp.Replace('.m_psz', '.data()').Replace('CW2A(', 'NarrowWindowsString(')
Set-Content -LiteralPath $storageCppPath -Value $storageCpp -Encoding utf8
$manifest = $manifest -replace 'dependency_overrides:', "dependency_overrides:`n  flutter_secure_storage_windows:`n    path: preview_plugins/flutter_secure_storage_windows"
Set-Content -LiteralPath (Join-Path $previewRoot 'pubspec.yaml') -Value $manifest -Encoding utf8

# Never report an offline write as saved when this preview cannot persist it.
$database = Get-Content (Join-Path $sourceRoot 'lib/services/local_db/app_database_stub.dart') -Raw
$database = $database -replace 'return id;', "throw UnsupportedError('Offline saving is unavailable in this desktop preview.');"
Set-Content -LiteralPath (Join-Path $previewRoot 'lib/services/local_db/app_database.dart') -Value $database -Encoding utf8
$providerPath = Join-Path $previewRoot 'lib/providers/user_provider.dart'
$provider = Get-Content $providerPath -Raw
$provider = $provider -replace 'bool get offlineModeEnabled => _offlineModeEnabled;', 'bool get offlineModeEnabled => false;'
Set-Content -LiteralPath $providerPath -Value $provider -Encoding utf8

Write-Host 'Windows preview: offline saving, text-to-speech, GPS, and native permission integration are disabled.'
Write-Host "Backend: $BackendUrl"
Push-Location $previewRoot
try {
    & $FlutterPath pub get --offline
    if ($LASTEXITCODE) { throw 'Could not resolve cached preview dependencies.' }
    if ($BuildOnly) {
        & $FlutterPath build windows --debug --no-pub "--dart-define=BACKEND_URL=$BackendUrl"
    } else {
        & $FlutterPath run -d windows --no-pub "--dart-define=BACKEND_URL=$BackendUrl"
    }
    if ($LASTEXITCODE) { throw 'The Windows preview failed. See the Flutter output above.' }
} finally { Pop-Location }
