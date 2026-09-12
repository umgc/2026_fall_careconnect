Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force -Path "dist" | Out-Null

    function Build-One {
        param(
            [string]$Goos,
            [string]$Goarch,
            [string]$Suffix
        )

        $out = "dist/careconnect-dev-toolkit-$Suffix"
        if ($Goos -eq "windows") {
            $out = "$out.exe"
        }

        Write-Host "building $out"
        $oldCgo = $env:CGO_ENABLED
        $oldGoos = $env:GOOS
        $oldGoarch = $env:GOARCH
        try {
            $env:CGO_ENABLED = "0"
            $env:GOOS = $Goos
            $env:GOARCH = $Goarch
            go build -trimpath -ldflags="-s -w" -o $out ./cmd/careconnect-dev
        }
        finally {
            $env:CGO_ENABLED = $oldCgo
            $env:GOOS = $oldGoos
            $env:GOARCH = $oldGoarch
        }
    }

    Build-One linux amd64 linux-amd64
    Build-One linux arm64 linux-arm64
    Build-One darwin amd64 darwin-amd64
    Build-One darwin arm64 darwin-arm64
    Build-One windows amd64 windows-amd64
    Build-One windows arm64 windows-arm64

    & "$PSScriptRoot/bootstrap.ps1"

    Write-Host "done. outputs are in dev-toolkit/dist/"
}
finally {
    Pop-Location
}
