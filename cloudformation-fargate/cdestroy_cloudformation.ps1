param(
    [ValidateSet("dev", "cfdemo", "staging", "prod")]
    [string]$Environment = "dev",

    [string]$Profile = "careconnect-sso",

    [string]$Region = "us-east-1",

    [switch]$SkipEcrCleanup
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:StartTime = Get-Date

# Track the active stack/operation so failures can point to the exact stage.
$script:CurrentStackName = $null
$script:CurrentOperation = $null
$script:HadNativePreference = $false
$nativePreferenceVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $nativePreferenceVar) {
    $script:HadNativePreference = $true
    $script:OriginalNativePreference = $nativePreferenceVar.Value
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ParameterDir = Join-Path $ScriptRoot "parameters"
$PlatformParameters = Join-Path $ParameterDir "$Environment-platform.json"

$StackPrefix = "careconnect"
$ServiceStackName = "$StackPrefix-service-$Environment"
$PlatformStackName = "$StackPrefix-platform-$Environment"
$DataStackName = "$StackPrefix-data-$Environment"
$NetworkingStackName = "$StackPrefix-networking-$Environment"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Assert-LastExitCode {
    param([string]$Context)
    if ($LASTEXITCODE -ne 0) {
        throw "$Context failed with exit code $LASTEXITCODE."
    }
}

function Get-ElapsedTimeText {
    $elapsed = (Get-Date) - $script:StartTime
    return "{0:00}:{1:00}:{2:00}" -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
}

function Get-StackStatus {
    param([string]$StackName)

    $status = & aws cloudformation describe-stacks `
        --profile $Profile `
        --region $Region `
        --stack-name $StackName `
        --query "Stacks[0].StackStatus" `
        --output text 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return [string]$status
}

function Write-StackFailureDetails {
    param([string]$StackName)

    $stackStatus = Get-StackStatus -StackName $StackName
    if ($stackStatus) {
        Write-Host ""
        Write-Host "Stack status: $stackStatus" -ForegroundColor Yellow
    }

    Write-Host "Recent failed CloudFormation events for '$StackName':" -ForegroundColor Yellow
    & aws cloudformation describe-stack-events `
        --profile $Profile `
        --region $Region `
        --stack-name $StackName `
        --query "StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]" `
        --output table
}

function Invoke-AwsProbe {
    param(
        [string[]]$Arguments
    )

    $nativePreferenceVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    $hadNativePreference = $null -ne $nativePreferenceVar

    try {
        if ($hadNativePreference) {
            $originalValue = $nativePreferenceVar.Value
            $global:PSNativeCommandUseErrorActionPreference = $false
        }

        try {
            & aws @Arguments 2>$null 1>$null
            return ($LASTEXITCODE -eq 0)
        }
        catch {
            return $false
        }
    }
    finally {
        if ($hadNativePreference) {
            $global:PSNativeCommandUseErrorActionPreference = $originalValue
        }
    }
}

function Test-StackExists {
    param([string]$StackName)

    return Invoke-AwsProbe -Arguments @(
        "cloudformation", "describe-stacks",
        "--profile", $Profile,
        "--region", $Region,
        "--stack-name", $StackName
    )
}

function Remove-CloudFormationStack {
    param([string]$StackName)

    $script:CurrentStackName = $StackName
    $script:CurrentOperation = "Deleting stack '$StackName'"

    # Teardown should be safe to rerun. If a stack is already gone, skip it.
    if (-not (Test-StackExists -StackName $StackName)) {
        Write-Host "Stack '$StackName' does not exist. Skipping." -ForegroundColor DarkYellow
        return
    }

    Write-Step "Deleting stack: $StackName"
    & aws cloudformation delete-stack `
        --profile $Profile `
        --region $Region `
        --stack-name $StackName
    Assert-LastExitCode "CloudFormation delete-stack for '$StackName'"

    & aws cloudformation wait stack-delete-complete `
        --profile $Profile `
        --region $Region `
        --stack-name $StackName
    Assert-LastExitCode "CloudFormation wait stack-delete-complete for '$StackName'"
}

function Get-RepositoryNameFromParameters {
    param([string]$ParameterFile)

    if (-not (Test-Path -LiteralPath $ParameterFile)) {
        return $null
    }

    $entries = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json
    foreach ($entry in $entries) {
        if ([string]$entry.ParameterKey -eq "RepositoryName") {
            return [string]$entry.ParameterValue
        }
    }

    return $null
}

function Test-EcrRepositoryExists {
    param([string]$RepositoryName)

    return Invoke-AwsProbe -Arguments @(
        "ecr", "describe-repositories",
        "--profile", $Profile,
        "--region", $Region,
        "--repository-names", $RepositoryName
    )
}

function Clear-EcrRepositoryImages {
    param([string]$RepositoryName)

    $script:CurrentOperation = "Cleaning ECR repository '$RepositoryName'"

    # The platform stack cannot be deleted while its ECR repo still contains
    # tagged or untagged images, so clear the repo first when possible.
    if (-not $RepositoryName) {
        Write-Host "No repository name was found for this environment. Skipping ECR cleanup." -ForegroundColor DarkYellow
        return
    }

    if (-not (Test-EcrRepositoryExists -RepositoryName $RepositoryName)) {
        Write-Host "ECR repository '$RepositoryName' does not exist. Skipping cleanup." -ForegroundColor DarkYellow
        return
    }

    Write-Step "Emptying ECR repository: $RepositoryName"

    while ($true) {
        $imageJson = & aws ecr list-images `
            --profile $Profile `
            --region $Region `
            --repository-name $RepositoryName `
            --output json
        Assert-LastExitCode "Listing images in ECR repository '$RepositoryName'"

        $payload = $imageJson | ConvertFrom-Json
        if (-not $payload.imageIds -or $payload.imageIds.Count -eq 0) {
            Write-Host "Repository '$RepositoryName' is already empty." -ForegroundColor Green
            break
        }

        $imageIds = @()
        foreach ($image in $payload.imageIds) {
            $hasImageTag = $null -ne $image.PSObject.Properties["imageTag"]
            $hasImageDigest = $null -ne $image.PSObject.Properties["imageDigest"]

            if ($hasImageTag -and $image.imageTag) {
                $imageIds += "imageTag=$($image.imageTag)"
            }
            elseif ($hasImageDigest -and $image.imageDigest) {
                $imageIds += "imageDigest=$($image.imageDigest)"
            }
        }

        if ($imageIds.Count -eq 0) {
            Write-Host "No deletable image identifiers were found in '$RepositoryName'." -ForegroundColor DarkYellow
            break
        }

        $deleteArgs = @(
            "ecr", "batch-delete-image",
            "--profile", $Profile,
            "--region", $Region,
            "--repository-name", $RepositoryName,
            "--image-ids"
        ) + $imageIds

        & aws @deleteArgs
        Assert-LastExitCode "Deleting images from ECR repository '$RepositoryName'"
    }
}

try {
    Write-Step "Checking prerequisites"
    if (-not (Test-CommandExists "aws")) {
        throw "Required command not found in PATH: aws"
    }

    Write-Step "Verifying AWS credentials for profile '$Profile'"
    $script:CurrentOperation = "Verifying AWS credentials"
    & aws sts get-caller-identity --profile $Profile --region $Region | Out-Null
    Assert-LastExitCode "AWS credential validation"

    # Delete in dependency order so later stacks are no longer referenced by
    # earlier ones: service -> platform -> data -> networking.
    Remove-CloudFormationStack -StackName $ServiceStackName

    if (-not $SkipEcrCleanup) {
        $RepositoryName = Get-RepositoryNameFromParameters -ParameterFile $PlatformParameters
        Clear-EcrRepositoryImages -RepositoryName $RepositoryName
        # The condition-detection sidecar repo is named "<RepositoryName>-dam-sidecar"
        # in 03-platform.yaml; it must be empty too or platform stack deletion fails.
        # Clear-EcrRepositoryImages skips it cleanly if it does not exist (e.g. a
        # platform stack that predates the sidecar).
        if ($RepositoryName) {
            Clear-EcrRepositoryImages -RepositoryName "$RepositoryName-dam-sidecar"
        }
    }
    else {
        Write-Host "Skipping ECR cleanup by request." -ForegroundColor DarkYellow
    }

    Remove-CloudFormationStack -StackName $PlatformStackName
    Remove-CloudFormationStack -StackName $DataStackName
    Remove-CloudFormationStack -StackName $NetworkingStackName

    Write-Step "Checking for remaining stacks in environment '$Environment'"
    $script:CurrentOperation = "Listing remaining stacks for environment '$Environment'"
    & aws cloudformation list-stacks `
        --profile $Profile `
        --region $Region `
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED ROLLBACK_COMPLETE `
        --query "StackSummaries[?contains(StackName, '$Environment')].[StackName,StackStatus]" `
        --output table
    Assert-LastExitCode "Final CloudFormation list-stacks check"

    $script:CurrentStackName = $null
    $script:CurrentOperation = $null

    Write-Host ""
    Write-Host "Teardown complete." -ForegroundColor Green
    Write-Host "Environment: $Environment"
    Write-Host "Elapsed time: $(Get-ElapsedTimeText)"
}
catch {
    Write-Host ""
    Write-Host "Teardown failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Elapsed time: $(Get-ElapsedTimeText)" -ForegroundColor Yellow

    if ($script:CurrentOperation) {
        Write-Host "Last operation: $script:CurrentOperation" -ForegroundColor Yellow
    }

    if ($script:CurrentStackName -and (Test-StackExists -StackName $script:CurrentStackName)) {
        Write-Host ""
        Write-Host "Troubleshooting for stack '$script:CurrentStackName':" -ForegroundColor Yellow
        Write-StackFailureDetails -StackName $script:CurrentStackName
        Write-Host "Manual command:" -ForegroundColor Yellow
        Write-Host "aws cloudformation describe-stack-events --profile $Profile --region $Region --stack-name $script:CurrentStackName --query `"StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]`" --output table" -ForegroundColor Yellow
    }

    exit 1
}
finally {
    if ($script:HadNativePreference) {
        $global:PSNativeCommandUseErrorActionPreference = $script:OriginalNativePreference
    }
}
