param(
    [ValidateSet("dev", "cfdemo", "staging", "prod")]
    [string]$Environment = "dev",

    [AllowEmptyString()]
    [string]$Profile = "",

    [string]$Region = "us-east-1",

    [string]$ImageTag,

    [switch]$RunTests,

    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:StartTime = Get-Date
$script:CurrentStackName = $null
$script:CurrentOperation = $null
$script:OriginalAwsProfile = $env:AWS_PROFILE
$script:HadNativePreference = $false

$nativePreferenceVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $nativePreferenceVar) {
    $script:HadNativePreference = $true
    $script:OriginalNativePreference = $nativePreferenceVar.Value
    $global:PSNativeCommandUseErrorActionPreference = $false
}

if ($Help) {
    @"
Usage: .\cdeploy_app_only.ps1 [options]

Options:
  -Environment <name>   Environment name: dev, cfdemo, staging, prod
  -Profile <profile>    Optional AWS CLI profile for local use
  -Region <region>      AWS region (default: us-east-1)
  -ImageTag <tag>       Docker/ECR image tag (default: env + git SHA or timestamp)
  -RunTests             Run Maven tests during package build
  -Help, -h             Show this help text
"@ | Write-Host
    exit 0
}

if (-not $ImageTag) {
    # App-only deploys should use unique tags so every pipeline run can be traced
    # back to a specific commit or build.
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitSha = & git -C (Split-Path -Parent $PSScriptRoot) rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitSha) {
            $ImageTag = "$Environment-$(([string]$gitSha).Trim())"
        }
    }

    if (-not $ImageTag) {
        $ImageTag = "$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"
    }
}

if ($Profile) {
    # Local developers can still target an AWS CLI profile, while GitHub Actions
    # can leave this empty and rely on the ambient temporary credentials.
    $env:AWS_PROFILE = $Profile
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$TemplateDir = Join-Path $ScriptRoot "templates"
$ParameterDir = Join-Path $ScriptRoot "parameters"
$BackendDir = Join-Path $RepoRoot "backend\core"

$StackPrefix = "careconnect"
$PlatformStackName = "$StackPrefix-platform-$Environment"
$ServiceStackName = "$StackPrefix-service-$Environment"

$ServiceTemplate = Join-Path $TemplateDir "04-service.yaml"
$ServiceParameters = Join-Path $ParameterDir "$Environment-service.json"

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

function Test-StackExists {
    param([string]$StackName)

    & aws cloudformation describe-stacks `
        --region $Region `
        --stack-name $StackName 2>$null 1>$null

    return ($LASTEXITCODE -eq 0)
}

function Get-StackStatus {
    param([string]$StackName)

    $status = & aws cloudformation describe-stacks `
        --region $Region `
        --stack-name $StackName `
        --query "Stacks[0].StackStatus" `
        --output text 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return [string]$status
}

function Remove-RollbackCompleteStack {
    param([string]$StackName)

    $stackStatus = Get-StackStatus -StackName $StackName
    if ($stackStatus -ne "ROLLBACK_COMPLETE") {
        return
    }

    Write-Host "Stack '$StackName' is in ROLLBACK_COMPLETE. Deleting it before retrying deployment..." -ForegroundColor Yellow
    & aws cloudformation delete-stack `
        --region $Region `
        --stack-name $StackName
    Assert-LastExitCode "CloudFormation delete-stack for rollback recovery on '$StackName'"

    & aws cloudformation wait stack-delete-complete `
        --region $Region `
        --stack-name $StackName
    Assert-LastExitCode "CloudFormation wait stack-delete-complete for rollback recovery on '$StackName'"
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
        --region $Region `
        --stack-name $StackName `
        --query "StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]" `
        --output table
}

function Assert-PathExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required path not found: $Path"
    }
}

function Get-ParameterOverrides {
    param(
        [string]$ParameterFile,
        [hashtable]$Overrides = @{}
    )

    # Read the checked-in JSON parameter file and convert it into the
    # Key=Value format expected by `aws cloudformation deploy`.
    $entries = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $entries) {
        $key = [string]$entry.ParameterKey
        $value = [string]$entry.ParameterValue

        if ($Overrides.ContainsKey($key)) {
            $value = [string]$Overrides[$key]
        }

        $result.Add("$key=$value")
    }

    return $result.ToArray()
}

function Invoke-CloudFormationDeploy {
    param(
        [string]$StackName,
        [string]$TemplatePath,
        [string]$ParameterFile,
        [hashtable]$Overrides = @{}
    )

    # The app-only deploy should only touch the ECS service stack. We still keep
    # the same hardened deploy logic as the full script so retries are safe.
    $script:CurrentStackName = $StackName
    Remove-RollbackCompleteStack -StackName $StackName
    $parameterOverrides = Get-ParameterOverrides -ParameterFile $ParameterFile -Overrides $Overrides
    $operation = if (Test-StackExists -StackName $StackName) { "Updating" } else { "Creating" }
    $script:CurrentOperation = "$operation stack '$StackName'"
    Write-Host "$operation stack '$StackName'..." -ForegroundColor DarkCyan

    $args = @(
        "cloudformation", "deploy",
        "--region", $Region,
        "--stack-name", $StackName,
        "--template-file", $TemplatePath,
        "--capabilities", "CAPABILITY_NAMED_IAM",
        "--no-fail-on-empty-changeset",
        "--parameter-overrides"
    ) + $parameterOverrides

    & aws @args
    if ($LASTEXITCODE -ne 0) {
        Write-StackFailureDetails -StackName $StackName
        throw "CloudFormation deploy for stack '$StackName' failed with exit code $LASTEXITCODE."
    }

    $finalStatus = Get-StackStatus -StackName $StackName
    if ($finalStatus) {
        Write-Host "Stack '$StackName' is now $finalStatus." -ForegroundColor Green
    }
}

function Get-CloudFormationOutput {
    param(
        [string]$StackName,
        [string]$OutputKey
    )

    $value = & aws cloudformation describe-stacks `
        --region $Region `
        --stack-name $StackName `
        --query "Stacks[0].Outputs[?OutputKey=='$OutputKey'].OutputValue" `
        --output text
    Assert-LastExitCode "Reading CloudFormation output '$OutputKey' from stack '$StackName'"
    return [string]$value
}

try {
    Write-Step "Checking prerequisites"
    foreach ($command in @("aws", "docker", "java")) {
        if (-not (Test-CommandExists $command)) {
            throw "Required command not found in PATH: $command"
        }
    }

    Assert-PathExists $ServiceTemplate
    Assert-PathExists $ServiceParameters
    Assert-PathExists $BackendDir

    if (-not (Test-Path -LiteralPath (Join-Path $BackendDir "mvnw.cmd"))) {
        throw "Expected Maven wrapper not found at '$BackendDir\mvnw.cmd'."
    }

    $credentialLabel = if ($Profile) { "profile '$Profile'" } else { "current AWS credentials" }
    Write-Step "Verifying AWS credentials for $credentialLabel"
    $script:CurrentOperation = "Verifying AWS credentials"
    & aws sts get-caller-identity --region $Region | Out-Null
    Assert-LastExitCode "AWS credential validation"

    if (-not (Test-StackExists -StackName $PlatformStackName)) {
        throw "Platform stack '$PlatformStackName' does not exist. Run the full deploy first so the ECR repository and ECS cluster are available."
    }

    Write-Step "Reading ECR repository URI"
    $script:CurrentOperation = "Reading ECR repository URI"
    $RepositoryUri = (Get-CloudFormationOutput -StackName $PlatformStackName -OutputKey "EcrRepositoryUri").Trim()
    if (-not $RepositoryUri -or $RepositoryUri -eq "None") {
        throw "Platform stack '$PlatformStackName' did not return EcrRepositoryUri."
    }

    $RepositoryName = ($RepositoryUri -split "/", 2)[1]
    $ImageUri = "$RepositoryUri`:$ImageTag"
    $LocalImageName = "careconnect-backend-local:$ImageTag"

    Write-Step "Building backend jar"
    Push-Location $BackendDir
    try {
        $script:CurrentOperation = "Building backend jar"
        # Use batch mode and suppress Maven transfer-progress spam so CI logs stay
        # readable and it is easier to tell whether the build is really moving.
        $mavenArgs = @("-B", "-ntp", "clean", "package", "-Pdocker")
        if (-not $RunTests) {
            $mavenArgs += "-DskipTests"
        }
        & .\mvnw.cmd @mavenArgs
        Assert-LastExitCode "Maven package build"

        Write-Step "Logging into ECR"
        $script:CurrentOperation = "Logging into ECR"
        $RegistryHost = ($RepositoryUri -split "/", 2)[0]
        $LoginPassword = & aws ecr get-login-password --region $Region
        Assert-LastExitCode "ECR login password retrieval"
        $LoginPassword | docker login --username AWS --password-stdin $RegistryHost
        Assert-LastExitCode "Docker login to ECR"

        Write-Step "Building Docker image"
        $script:CurrentOperation = "Building Docker image"
        & docker build -t $LocalImageName .
        Assert-LastExitCode "Docker build"

        Write-Step "Tagging and pushing Docker image to ECR"
        $script:CurrentOperation = "Pushing Docker image to ECR"
        & docker tag $LocalImageName $ImageUri
        Assert-LastExitCode "Docker tag"
        & docker push $ImageUri
        Assert-LastExitCode "Docker push"
    }
    finally {
        Pop-Location
    }

    Write-Step "Deploying service stack: $ServiceStackName"
    $ServiceOverrides = @{
        BackendImageUri = $ImageUri
    }
    Invoke-CloudFormationDeploy -StackName $ServiceStackName -TemplatePath $ServiceTemplate -ParameterFile $ServiceParameters -Overrides $ServiceOverrides

    Write-Step "Reading final API endpoint"
    $script:CurrentOperation = "Reading final API endpoint"
    $ApiEndpoint = (Get-CloudFormationOutput -StackName $ServiceStackName -OutputKey "ApiEndpoint").Trim()
    $script:CurrentStackName = $null
    $script:CurrentOperation = $null

    Write-Host ""
    Write-Host "App-only deployment complete." -ForegroundColor Green
    Write-Host "Environment:   $Environment"
    Write-Host "Repository:    $RepositoryName"
    Write-Host "Image URI:     $ImageUri"
    Write-Host "API Endpoint:  $ApiEndpoint"
    Write-Host "Health check:  $ApiEndpoint/v1/api/test/health"
    Write-Host "Elapsed time:  $(Get-ElapsedTimeText)"
}
catch {
    Write-Host ""
    Write-Host "App-only deployment failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Elapsed time: $(Get-ElapsedTimeText)" -ForegroundColor Yellow

    if ($script:CurrentStackName) {
        Write-Host ""
        Write-Host "Troubleshoot this stack with:" -ForegroundColor Yellow
        Write-Host "aws cloudformation describe-stack-events --region $Region --stack-name $script:CurrentStackName --query `"StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]`" --output table" -ForegroundColor Yellow
    }

    exit 1
}
finally {
    if ($Profile) {
        $env:AWS_PROFILE = $script:OriginalAwsProfile
    }

    if ($script:HadNativePreference) {
        $global:PSNativeCommandUseErrorActionPreference = $script:OriginalNativePreference
    }
}
