Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

# Where prebuilt binaries are published. Override to use a fork or pin a tag.
$devToolkitRepo = if ($env:DEV_TOOLKIT_REPO) { $env:DEV_TOOLKIT_REPO } else { "umgc/2026_fall_careconnect" }
$devToolkitVersion = if ($env:DEV_TOOLKIT_VERSION) { $env:DEV_TOOLKIT_VERSION } else { "latest" }
# Set to 1 to skip the release download and build from source instead.
$devToolkitOffline = ($env:DEV_TOOLKIT_OFFLINE -eq "1")

function Get-HostTarget {
    $platform = [System.Environment]::OSVersion.Platform

    if ($platform -eq [System.PlatformID]::Win32NT) {
        $goos = "windows"
    }
    elseif ((Get-Variable -Name IsMacOS -Scope Global -ErrorAction SilentlyContinue) -and $IsMacOS) {
        $goos = "darwin"
    }
    elseif ((Get-Variable -Name IsLinux -Scope Global -ErrorAction SilentlyContinue) -and $IsLinux) {
        $goos = "linux"
    }
    else {
        $uname = (& uname -s).Trim()
        switch -Wildcard ($uname) {
            "Darwin" { $goos = "darwin" }
            "Linux" { $goos = "linux" }
            default { throw "unsupported OS: $uname" }
        }
    }

    if ($goos -eq "windows") {
        $archName = $env:PROCESSOR_ARCHITECTURE
        if ([string]::IsNullOrWhiteSpace($archName)) {
            $archName = $env:PROCESSOR_ARCHITEW6432
        }
    }
    else {
        $archName = (& uname -m).Trim()
    }

    switch -Regex ($archName) {
        "^(AMD64|x86_64|amd64)$" { $goarch = "amd64" }
        "^(ARM64|arm64|aarch64)$" { $goarch = "arm64" }
        default { throw "unsupported architecture: $archName" }
    }

    $target = "$goos/$goarch"
    $supported = @("linux/amd64", "linux/arm64", "darwin/amd64", "darwin/arm64", "windows/amd64", "windows/arm64")
    if ($supported -notcontains $target) {
        throw "unsupported binary target: $target"
    }

    [PSCustomObject]@{
        Goos = $goos
        Goarch = $goarch
    }
}

function Get-ReleaseUrl {
    param([string]$Asset)

    if ($devToolkitVersion -eq "latest") {
        return "https://github.com/$devToolkitRepo/releases/latest/download/$Asset"
    }

    return "https://github.com/$devToolkitRepo/releases/download/$devToolkitVersion/$Asset"
}

# Downloads the release asset for this machine. Returns $false when the asset is
# missing or the network is unavailable.
function Get-ReleaseAsset {
    param([string]$Asset, [string]$Destination)

    $url = Get-ReleaseUrl -Asset $Asset
    $tmp = "$Destination.download"

    Write-Host "fetching $Asset from the $devToolkitVersion release of $devToolkitRepo"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        # Older runtimes may not expose this; the download can still succeed.
    }

    $progress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        # A 404 simply means this platform has no published asset yet, which is
        # an expected fallback path rather than a failure worth reporting.
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    }
    catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }
    finally {
        $ProgressPreference = $progress
    }

    # A zero-length file means the redirect resolved but the asset did not.
    if (-not (Test-Path -LiteralPath $tmp -PathType Leaf) -or (Get-Item -LiteralPath $tmp).Length -eq 0) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }

    Move-Item -LiteralPath $tmp -Destination $Destination -Force
    Write-Host "downloaded: dev-toolkit/dist/$Asset"
    return $true
}

function Build-FromSource {
    param([string]$Goos, [string]$Goarch, [string]$Destination)

    Write-Host "building $Goos/$Goarch from source"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null

    $previous = @{
        CGO_ENABLED = $env:CGO_ENABLED
        GOOS = $env:GOOS
        GOARCH = $env:GOARCH
    }

    Push-Location $PSScriptRoot
    try {
        $env:CGO_ENABLED = "0"
        $env:GOOS = $Goos
        $env:GOARCH = $Goarch
        # Quoting matches build.ps1, which is known to work on Windows.
        go build -trimpath -ldflags="-s -w" -o $Destination ./cmd/careconnect-dev
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
    }
    finally {
        Pop-Location
        $env:CGO_ENABLED = $previous.CGO_ENABLED
        $env:GOOS = $previous.GOOS
        $env:GOARCH = $previous.GOARCH
    }

    Write-Host "built: dev-toolkit/dist/$(Split-Path -Leaf $Destination)"
    return $true
}

function Assert-BinaryAvailable {
    param([string]$Asset, [string]$Target)

    throw @"

No dev-toolkit binary is available for $Target, and one could not be obtained
automatically:

  - not found locally at dev-toolkit/dist/$Asset
  - not published in the $devToolkitVersion release of $devToolkitRepo
  - Go is not installed, so it cannot be built from source

Do one of the following, then rerun this script:

  1. Install Go 1.22 or newer (https://go.dev/dl/) and rerun bootstrap. It will
     build just the binary for this machine.
  2. Download $Asset from
     https://github.com/$devToolkitRepo/releases
     and place it in dev-toolkit\dist\.
"@
}

# Resolution order: an existing local binary wins so that build.ps1, which calls
# this script after building, never re-downloads what it just produced.
function Resolve-Binary {
    param([string]$Asset, [string]$Destination, [string]$Goos, [string]$Goarch)

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        Write-Host "using existing binary: dev-toolkit/dist/$Asset"
        return
    }

    if (-not $devToolkitOffline) {
        if (Get-ReleaseAsset -Asset $Asset -Destination $Destination) {
            return
        }
        Write-Warning "no release asset available; falling back to a local build"
    }

    if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
        Assert-BinaryAvailable -Asset $Asset -Target "$Goos/$Goarch"
    }

    if (-not (Build-FromSource -Goos $Goos -Goarch $Goarch -Destination $Destination)) {
        throw "go build failed for $Goos/$Goarch"
    }
}

function New-WindowsCmdLauncher {
    param([string]$BinaryName)

    $cmdPath = Join-Path $repoRoot "dev-tool.cmd"
    $content = @(
        "@echo off",
        'set "SCRIPT_DIR=%~dp0"',
        "`"%SCRIPT_DIR%dev-toolkit\dist\$BinaryName`" %*"
    )
    Set-Content -LiteralPath $cmdPath -Value $content -Encoding ASCII
    Write-Host "windows launcher: dev-tool.cmd -> dev-toolkit/dist/$BinaryName"
}

function New-DevToolSymlink {
    param([string]$TargetRelative)

    $link = Join-Path $repoRoot "dev-tool"
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Remove-Item -LiteralPath $link -Force
        }
        else {
            throw "cannot create launcher: dev-tool already exists and is not a symlink"
        }
    }

    New-Item -ItemType SymbolicLink -Path $link -Target $TargetRelative | Out-Null
    Write-Host "launcher: dev-tool -> $TargetRelative"
}

$hostTarget = Get-HostTarget
$binaryName = "careconnect-dev-toolkit-$($hostTarget.Goos)-$($hostTarget.Goarch)"
if ($hostTarget.Goos -eq "windows") {
    $binaryName = "$binaryName.exe"
}

$targetRelative = Join-Path "dev-toolkit" (Join-Path "dist" $binaryName)
$targetAbsolute = Join-Path $repoRoot $targetRelative

Resolve-Binary -Asset $binaryName -Destination $targetAbsolute `
    -Goos $hostTarget.Goos -Goarch $hostTarget.Goarch

if ($hostTarget.Goos -eq "windows") {
    New-WindowsCmdLauncher -BinaryName $binaryName
    try {
        New-DevToolSymlink -TargetRelative $targetRelative
    }
    catch {
        Write-Warning "windows symlink was not created: $($_.Exception.Message)"
        Write-Warning "Use .\dev-tool.cmd, or enable Developer Mode/run elevated and rerun bootstrap.ps1."
    }
}
else {
    New-DevToolSymlink -TargetRelative $targetRelative
}
