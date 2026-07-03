# Wire EventBridge → ngrok → local backend for Chime KVS stream discovery.
# Usage: .\scripts\wire-chime-kvs-eventbridge-local.ps1 -NgrokBaseUrl https://abc123.ngrok-free.app
# Re-run when ngrok URL changes (updates API destination endpoint).

param(
    [Parameter(Mandatory = $true)]
    [string]$NgrokBaseUrl,
    [string]$Region = "us-east-1",
    [string]$NamePrefix = "careconnect-local-chime-kvs"
)

$ErrorActionPreference = "Stop"
$NgrokBaseUrl = $NgrokBaseUrl.TrimEnd("/")
$Endpoint = "$NgrokBaseUrl/api/internal/chime/media-stream-events"
$ConnectionName = $NamePrefix
$DestinationName = $NamePrefix
$RuleName = "$NamePrefix-stream-start"
$RoleName = "$NamePrefix-invoke"

Write-Host "Endpoint: $Endpoint"

function Get-ConnectionArn {
    $arn = aws events list-connections --name-prefix $ConnectionName --region $Region `
        --query "Connections[?Name=='$ConnectionName'].ConnectionArn | [0]" --output text 2>$null
    if ($arn -and $arn -ne "None") { return $arn }
    return $null
}

$connArn = Get-ConnectionArn
if (-not $connArn) {
    Write-Host "Creating EventBridge connection $ConnectionName ..."
    $authJson = '{"ApiKeyAuthParameters":{"ApiKeyName":"X-EventBridge-Connection","ApiKeyValue":"local-dev"}}'
    $connArn = aws events create-connection --name $ConnectionName `
        --authorization-type API_KEY --auth-parameters $authJson `
        --region $Region --query ConnectionArn --output text
}
Write-Host "ConnectionArn: $connArn"

$destArn = aws events describe-api-destination --name $DestinationName --region $Region `
    --query ApiDestinationArn --output text 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating API destination $DestinationName ..."
    $destArn = aws events create-api-destination --name $DestinationName `
        --connection-arn $connArn --invocation-endpoint $Endpoint --http-method POST `
        --invocation-rate-limit-per-second 10 --region $Region `
        --query ApiDestinationArn --output text
} else {
    Write-Host "Updating API destination endpoint ..."
    aws events update-api-destination --name $DestinationName `
        --invocation-endpoint $Endpoint --region $Region | Out-Null
}
Write-Host "ApiDestinationArn: $destArn"

$roleArn = aws iam get-role --role-name $RoleName --query Role.Arn --output text 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating IAM role $RoleName ..."
    $trust = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    $roleArn = aws iam create-role --role-name $RoleName --assume-role-policy-document $trust `
        --query Role.Arn --output text
    $policy = "{`"Version`":`"2012-10-17`",`"Statement`":[{`"Effect`":`"Allow`",`"Action`":`"events:InvokeApiDestination`",`"Resource`":`"$destArn`"}]}"
    aws iam put-role-policy --role-name $RoleName --policy-name InvokeApiDestination --policy-document $policy | Out-Null
    Start-Sleep -Seconds 5
}
Write-Host "RoleArn: $roleArn"

$eventPattern = '{"source":["aws.chime"],"detail-type":["Chime Media Pipeline State Change"],"detail":{"eventType":["chime:MediaPipelineKinesisVideoStreamStart"]}}'
aws events put-rule --name $RuleName --event-pattern $eventPattern `
    --state ENABLED --description "Local ngrok: Chime KVS stream start to backend webhook" `
    --region $Region | Out-Null

aws events put-targets --rule $RuleName --region $Region --targets "Id=webhook,Arn=$destArn,RoleArn=$roleArn" | Out-Null

Write-Host ""
Write-Host "Done. Ensure backend has CARECONNECT_KVS_EVENT_WEBHOOK_ENABLED=true and restart."
Write-Host "Smoke: curl -X POST $Endpoint -H 'Content-Type: application/json' -d '{\"detail\":{}}'"
