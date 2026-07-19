# Wire EventBridge -> ngrok -> local backend for Chime KVS stream discovery.
# Usage: .\scripts\wire-chime-kvs-eventbridge-local.ps1 -NgrokBaseUrl https://YOUR-STABLE-SUBDOMAIN.ngrok-free.app
# Prefer a reserved ngrok domain (logged-in account) so the URL stays stable across restarts.
# Re-run only when the public base URL changes (updates the API destination endpoint).
#
# PowerShell note: AWS CLI JSON args are written to temp files (file://) so quotes are not stripped.

param(
    [Parameter(Mandatory = $true)]
    [string]$NgrokBaseUrl,
    [string]$Region = "us-east-1",
    [string]$NamePrefix = "careconnect-local-chime-kvs",
    [string]$SharedSecret = "local-dev"
)

$ErrorActionPreference = "Continue"
$NgrokBaseUrl = $NgrokBaseUrl.TrimEnd("/")
$Endpoint = "$NgrokBaseUrl/api/internal/chime/media-stream-events"
$ConnectionName = $NamePrefix
$DestinationName = $NamePrefix
$RuleName = "$NamePrefix-stream-start"
$RoleName = "$NamePrefix-invoke"
$TempDir = Join-Path $env:TEMP "careconnect-kvs-eb-$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Write-JsonFile([string]$Name, [string]$Json) {
    $path = Join-Path $TempDir $Name
    [System.IO.File]::WriteAllText($path, $Json, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

Write-Host "Endpoint: $Endpoint"
Write-Host "Shared secret (X-EventBridge-Connection): $SharedSecret"

try {
    $connArn = (& aws events list-connections --name-prefix $ConnectionName --region $Region `
        --query "Connections[?Name=='$ConnectionName'].ConnectionArn | [0]" --output text 2>$null)
    if (-not $connArn -or $connArn -eq "None") {
        Write-Host "Creating EventBridge connection $ConnectionName ..."
        $authPath = Write-JsonFile "auth.json" (@{
            ApiKeyAuthParameters = @{
                ApiKeyName  = "X-EventBridge-Connection"
                ApiKeyValue = $SharedSecret
            }
        } | ConvertTo-Json -Compress -Depth 5)
        $connArn = (& aws events create-connection --name $ConnectionName `
            --authorization-type API_KEY `
            --auth-parameters "file://$authPath" `
            --region $Region `
            --query ConnectionArn `
            --output text)
        if ($LASTEXITCODE -ne 0) {
            throw "create-connection failed (exit $LASTEXITCODE)"
        }
    }
    if (-not $connArn -or $connArn -eq "None") {
        throw "Could not resolve ConnectionArn for $ConnectionName"
    }
    Write-Host "ConnectionArn: $connArn"

    $destArn = (& aws events describe-api-destination --name $DestinationName --region $Region `
        --query ApiDestinationArn --output text 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $destArn -or $destArn -eq "None") {
        Write-Host "Creating API destination $DestinationName ..."
        $destArn = (& aws events create-api-destination --name $DestinationName `
            --connection-arn $connArn --invocation-endpoint $Endpoint --http-method POST `
            --invocation-rate-limit-per-second 10 --region $Region `
            --query ApiDestinationArn --output text)
        if ($LASTEXITCODE -ne 0) { throw "create-api-destination failed (exit $LASTEXITCODE)" }
    } else {
        Write-Host "Updating API destination endpoint ..."
        & aws events update-api-destination --name $DestinationName `
            --connection-arn $connArn `
            --invocation-endpoint $Endpoint --region $Region | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "update-api-destination failed (exit $LASTEXITCODE)" }
    }
    Write-Host "ApiDestinationArn: $destArn"

    $roleArn = (& aws iam get-role --role-name $RoleName --query Role.Arn --output text 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $roleArn -or $roleArn -eq "None") {
        Write-Host "Creating IAM role $RoleName ..."
        $trustPath = Write-JsonFile "trust.json" (@{
            Version = "2012-10-17"
            Statement = @(
                @{
                    Effect = "Allow"
                    Principal = @{ Service = "events.amazonaws.com" }
                    Action = "sts:AssumeRole"
                }
            )
        } | ConvertTo-Json -Compress -Depth 6)
        $roleArn = (& aws iam create-role --role-name $RoleName `
            --assume-role-policy-document "file://$trustPath" `
            --query Role.Arn --output text)
        if ($LASTEXITCODE -ne 0) { throw "create-role failed (exit $LASTEXITCODE)" }

        $policyPath = Write-JsonFile "policy.json" (@{
            Version = "2012-10-17"
            Statement = @(
                @{
                    Effect = "Allow"
                    Action = "events:InvokeApiDestination"
                    Resource = $destArn
                }
            )
        } | ConvertTo-Json -Compress -Depth 6)
        & aws iam put-role-policy --role-name $RoleName `
            --policy-name InvokeApiDestination `
            --policy-document "file://$policyPath" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "put-role-policy failed (exit $LASTEXITCODE)" }
        Start-Sleep -Seconds 5
    }
    Write-Host "RoleArn: $roleArn"

    $patternPath = Write-JsonFile "event-pattern.json" (@{
        source = @("aws.chime")
        "detail-type" = @("Chime Media Pipeline State Change")
        detail = @{
            eventType = @("chime:MediaPipelineKinesisVideoStreamStart")
        }
    } | ConvertTo-Json -Compress -Depth 6)
    & aws events put-rule --name $RuleName `
        --event-pattern "file://$patternPath" `
        --state ENABLED `
        --description "Local ngrok: Chime KVS stream start to backend webhook" `
        --region $Region | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "put-rule failed (exit $LASTEXITCODE)" }

    $targetsObj = @(
        @{
            Id = "webhook"
            Arn = $destArn
            RoleArn = $roleArn
        }
    )
    $targetsJson = ConvertTo-Json -InputObject $targetsObj -Compress -Depth 6
    if (-not $targetsJson.TrimStart().StartsWith("[")) {
        $targetsJson = "[$targetsJson]"
    }
    $targetsPath = Write-JsonFile "targets.json" $targetsJson
    & aws events put-targets --rule $RuleName --region $Region --targets "file://$targetsPath" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "put-targets failed (exit $LASTEXITCODE)" }

    Write-Host ""
    Write-Host "Done. Ensure backend has:"
    Write-Host "  CARECONNECT_KVS_EVENT_WEBHOOK_ENABLED=true"
    Write-Host "  CARECONNECT_KVS_EVENT_WEBHOOK_SHARED_SECRET=$SharedSecret"
    Write-Host "Then restart the backend."
    Write-Host "Smoke (PowerShell):"
    Write-Host "  Invoke-RestMethod -Method POST -Uri '$Endpoint' -Headers @{ 'X-EventBridge-Connection' = '$SharedSecret' } -ContentType 'application/json' -Body '{""detail"":{}}'"
    Write-Host "Security: ngrok exposes this webhook publicly - keep the shared secret set and do not commit real secrets."
}
finally {
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
    }
}
