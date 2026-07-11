param(
    [ValidateSet("dev", "cfdemo", "staging", "prod")]
    [string]$Environment = "dev",

    [string]$Profile = "careconnect-sso",

    [string]$Region = "us-east-1",

    [string]$ImageTag,

    [switch]$RunTests
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:StartTime = Get-Date

# Track the active stack/operation so the catch block can print useful context.
$script:CurrentStackName = $null
$script:CurrentOperation = $null
$script:HadNativePreference = $false
$nativePreferenceVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $nativePreferenceVar) {
    $script:HadNativePreference = $true
    $script:OriginalNativePreference = $nativePreferenceVar.Value
    $global:PSNativeCommandUseErrorActionPreference = $false
}

if (-not $ImageTag) {
    # Default the image tag to the environment name so dev/cfdemo stay separate.
    $ImageTag = $Environment
}

# Resolve repository-relative paths so the script works from any starting folder.
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$TemplateDir = Join-Path $ScriptRoot "templates"
$ParameterDir = Join-Path $ScriptRoot "parameters"
$BackendDir = Join-Path $RepoRoot "backend\core"

$StackPrefix = "careconnect"
$NetworkingStackName = "$StackPrefix-networking-$Environment"
$DataStackName = "$StackPrefix-data-$Environment"
$PlatformStackName = "$StackPrefix-platform-$Environment"
$ServiceStackName = "$StackPrefix-service-$Environment"

$NetworkingTemplate = Join-Path $TemplateDir "01-networking.yaml"
$DataTemplate = Join-Path $TemplateDir "02-data.yaml"
$PlatformTemplate = Join-Path $TemplateDir "03-platform.yaml"
$ServiceTemplate = Join-Path $TemplateDir "04-service.yaml"

$NetworkingParameters = Join-Path $ParameterDir "$Environment-networking.json"
$DataParameters = Join-Path $ParameterDir "$Environment-data.json"
$PlatformParameters = Join-Path $ParameterDir "$Environment-platform.json"
$ServiceParameters = Join-Path $ParameterDir "$Environment-service.json"
$script:DataEffectiveParameters = $DataParameters
$script:TemporaryFiles = New-Object System.Collections.Generic.List[string]

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

    try {
        & aws cloudformation describe-stacks `
            --profile $Profile `
            --region $Region `
            --stack-name $StackName 2>$null 1>$null
    }
    catch {
        return $false
    }

    return ($LASTEXITCODE -eq 0)
}

function Test-EcrRepositoryExists {
    param([string]$RepositoryName)

    try {
        & aws ecr describe-repositories `
            --profile $Profile `
            --region $Region `
            --repository-names $RepositoryName 2>$null 1>$null
    }
    catch {
        return $false
    }

    return ($LASTEXITCODE -eq 0)
}

function Get-StackStatus {
    param([string]$StackName)

    try {
        $status = & aws cloudformation describe-stacks `
            --profile $Profile `
            --region $Region `
            --stack-name $StackName `
            --query "Stacks[0].StackStatus" `
            --output text 2>$null
    }
    catch {
        return $null
    }

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return [string]$status
}

function Wait-ForStackStable {
    param([string]$StackName)

    $status = Get-StackStatus -StackName $StackName
    if (-not $status) {
        return
    }

    if ($status -eq "CREATE_IN_PROGRESS") {
        Write-Host "Stack '$StackName' is still being created (RDS can take 10-20 minutes). Waiting for CREATE_COMPLETE..." -ForegroundColor Yellow
        $script:CurrentOperation = "Waiting for stack '$StackName' to finish creating"
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & aws cloudformation wait stack-create-complete `
                --profile $Profile `
                --region $Region `
                --stack-name $StackName 2>&1 | Out-Null
            Assert-LastExitCode "CloudFormation wait stack-create-complete for '$StackName'"
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        return
    }

    if ($status -in @("UPDATE_IN_PROGRESS", "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS")) {
        Write-Host "Stack '$StackName' is still updating. Waiting..." -ForegroundColor Yellow
        $script:CurrentOperation = "Waiting for stack '$StackName' to finish updating"
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & aws cloudformation wait stack-update-complete `
                --profile $Profile `
                --region $Region `
                --stack-name $StackName 2>&1 | Out-Null
            Assert-LastExitCode "CloudFormation wait stack-update-complete for '$StackName'"
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
}

function Get-ParameterMap {
    param([string]$ParameterFile)

    $entries = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json
    $map = @{}

    foreach ($entry in $entries) {
        $map[[string]$entry.ParameterKey] = [string]$entry.ParameterValue
    }

    return $map
}

function Merge-ParameterMaps {
    param(
        [hashtable]$BaseMap,
        [hashtable]$OverlayMap
    )

    $merged = @{}
    foreach ($key in $BaseMap.Keys) {
        $merged[$key] = $BaseMap[$key]
    }

    foreach ($key in $OverlayMap.Keys) {
        $merged[$key] = $OverlayMap[$key]
    }

    return $merged
}

function Get-DataSecretOverrides {
    $overrides = @{}

    if ($env:CARECONNECT_DATABASE_MASTER_PASSWORD) {
        $overrides["DatabaseMasterPassword"] = [string]$env:CARECONNECT_DATABASE_MASTER_PASSWORD
    }

    if ($env:CARECONNECT_JWT_SECRET) {
        $overrides["JwtSecret"] = [string]$env:CARECONNECT_JWT_SECRET
    }

    return $overrides
}

function New-EffectiveParameterFile {
    param(
        [string]$BaseParameterFile,
        [hashtable]$Overrides = @{}
    )

    if ($Overrides.Count -eq 0) {
        return $BaseParameterFile
    }

    # Build one effective parameter file at runtime so local shells and GitHub
    # Actions can inject sensitive values without committing them to Git.
    $baseMap = Get-ParameterMap -ParameterFile $BaseParameterFile
    $mergedMap = Merge-ParameterMaps -BaseMap $baseMap -OverlayMap $Overrides

    $entries = Get-Content -LiteralPath $BaseParameterFile -Raw | ConvertFrom-Json
    foreach ($entry in $entries) {
        $key = [string]$entry.ParameterKey
        if ($mergedMap.ContainsKey($key)) {
            $entry.ParameterValue = [string]$mergedMap[$key]
        }
    }

    foreach ($key in $mergedMap.Keys) {
        if (-not ($entries | Where-Object { [string]$_.ParameterKey -eq $key })) {
            $entries += [pscustomobject]@{
                ParameterKey = $key
                ParameterValue = [string]$mergedMap[$key]
            }
        }
    }

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("careconnect-$Environment-data-" + [System.Guid]::NewGuid().ToString() + ".json")
    $entries | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tempFile -Encoding UTF8
    $script:TemporaryFiles.Add($tempFile)
    return $tempFile
}

function Remove-RollbackCompleteStack {
    param([string]$StackName)

    $stackStatus = Get-StackStatus -StackName $StackName
    if ($stackStatus -ne "ROLLBACK_COMPLETE") {
        return
    }

    Write-Host "Stack '$StackName' is in ROLLBACK_COMPLETE. Deleting it before retrying deployment..." -ForegroundColor Yellow
    & aws cloudformation delete-stack `
        --profile $Profile `
        --region $Region `
        --stack-name $StackName
    Assert-LastExitCode "CloudFormation delete-stack for rollback recovery on '$StackName'"

    & aws cloudformation wait stack-delete-complete `
        --profile $Profile `
        --region $Region `
        --stack-name $StackName
    Assert-LastExitCode "CloudFormation wait stack-delete-complete for rollback recovery on '$StackName'"
}

function Write-StackFailureDetails {
    param([string]$StackName)

    if (-not (Test-StackExists -StackName $StackName)) {
        Write-Host ""
        Write-Host "Stack '$StackName' does not exist yet. The failure likely happened during parameter validation or change set creation." -ForegroundColor Yellow
        return
    }

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

        $escapedValue = $value.Replace('"', '\"')
        $result.Add("$key=`"$escapedValue`"")
    }

    return $result.ToArray()
}

function Test-PlaceholderValue {
    param(
        [string]$ParameterFile,
        [string[]]$DisallowedFragments
    )

    $entries = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json
    foreach ($entry in $entries) {
        $value = [string]$entry.ParameterValue
        foreach ($fragment in $DisallowedFragments) {
            if ($value -like "*$fragment*") {
                throw "Parameter file '$ParameterFile' still contains a placeholder value for '$($entry.ParameterKey)'."
            }
        }
    }
}

function Assert-ParameterMinLength {
    param(
        [string]$ParameterFile,
        [string]$ParameterKey,
        [int]$MinLength
    )

    $parameterMap = Get-ParameterMap -ParameterFile $ParameterFile
    if (-not $parameterMap.ContainsKey($ParameterKey)) {
        return
    }

    $value = [string]$parameterMap[$ParameterKey]
    if ($value.Length -lt $MinLength) {
        throw "Parameter '$ParameterKey' in '$ParameterFile' must contain at least $MinLength characters."
    }
}

function Assert-HealthCheckPathValue {
    param([string]$ParameterFile)

    $parameterMap = Get-ParameterMap -ParameterFile $ParameterFile
    if (-not $parameterMap.ContainsKey("HealthCheckPath")) {
        return
    }

    $value = [string]$parameterMap["HealthCheckPath"]
    if (-not $value.StartsWith("/")) {
        throw "Parameter 'HealthCheckPath' in '$ParameterFile' must start with '/'."
    }

    if ($value -match "\s") {
        throw "Parameter 'HealthCheckPath' in '$ParameterFile' cannot contain spaces."
    }
}

function Assert-PlatformRepositoryNameAvailable {
    param([string]$ParameterFile)

    $parameterMap = Get-ParameterMap -ParameterFile $ParameterFile
    if (-not $parameterMap.ContainsKey("RepositoryName")) {
        return
    }

    $repositoryName = [string]$parameterMap["RepositoryName"]
    if (-not $repositoryName) {
        return
    }

    if ((-not (Test-StackExists -StackName $PlatformStackName)) -and (Test-EcrRepositoryExists -RepositoryName $repositoryName)) {
        throw "ECR repository '$repositoryName' already exists in AWS. Choose a unique RepositoryName in '$ParameterFile' or deploy into the stack that already owns it."
    }
}

function Invoke-CloudFormationDeploy {
    param(
        [string]$StackName,
        [string]$TemplatePath,
        [string]$ParameterFile,
        [hashtable]$Overrides = @{}
    )

    # CloudFormation deploy handles both create and update. We still detect the
    # current state so the user can see which path is happening.
    $script:CurrentStackName = $StackName
    $script:CurrentOperation = "Preparing deployment for '$StackName'"
    Wait-ForStackStable -StackName $StackName
    Remove-RollbackCompleteStack -StackName $StackName
    $parameterOverrides = Get-ParameterOverrides -ParameterFile $ParameterFile -Overrides $Overrides
    $operation = if (Test-StackExists -StackName $StackName) { "Updating" } else { "Creating" }
    $script:CurrentOperation = "$operation stack '$StackName'"
    Write-Host "$operation stack '$StackName'..." -ForegroundColor DarkCyan

    $args = @(
        "cloudformation", "deploy",
        "--profile", $Profile,
        "--region", $Region,
        "--stack-name", $StackName,
        "--template-file", $TemplatePath,
        "--capabilities", "CAPABILITY_NAMED_IAM",
        "--no-fail-on-empty-changeset",
        "--parameter-overrides"
    ) + $parameterOverrides

    $hadNativePref = $false
    $previousNativePreference = $null
    $nativePreferenceVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $nativePreferenceVar) {
        $hadNativePref = $true
        $previousNativePreference = $nativePreferenceVar.Value
        $global:PSNativeCommandUseErrorActionPreference = $false
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $awsOutput = $null
    $deployExitCode = 1
    try {
        # AWS CLI writes progress to stderr. Some PowerShell versions still surface
        # that as a terminating error, so catch it and rely on LASTEXITCODE.
        try {
            $awsOutput = & aws @args 2>&1
            $deployExitCode = $LASTEXITCODE
        }
        catch {
            if ($null -eq $awsOutput) {
                $awsOutput = @()
            }
            $awsOutput += $_.Exception.Message
            $awsOutput += $_.ToString()
            if ($LASTEXITCODE -ne 0) {
                $deployExitCode = $LASTEXITCODE
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hadNativePref) {
            $global:PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }

    if ($awsOutput) {
        Write-Host $awsOutput
    }

    if ($deployExitCode -ne 0) {
        try {
            Write-StackFailureDetails -StackName $StackName
        }
        catch {
            Write-Host "Unable to read CloudFormation failure details for '$StackName'." -ForegroundColor Yellow
        }
        throw "CloudFormation deploy for stack '$StackName' failed with exit code $deployExitCode."
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
        --profile $Profile `
        --region $Region `
        --stack-name $StackName `
        --query "Stacks[0].Outputs[?OutputKey=='$OutputKey'].OutputValue" `
        --output text
    Assert-LastExitCode "Reading CloudFormation output '$OutputKey' from stack '$StackName'"
    return [string]$value
}

try {
Write-Step "Checking prerequisites"
    foreach ($command in @("aws", "docker", "git", "java")) {
        if (-not (Test-CommandExists $command)) {
            throw "Required command not found in PATH: $command"
        }
    }

    Assert-PathExists $NetworkingTemplate
    Assert-PathExists $DataTemplate
    Assert-PathExists $PlatformTemplate
    Assert-PathExists $ServiceTemplate
    Assert-PathExists $NetworkingParameters
    Assert-PathExists $DataParameters
    Assert-PathExists $PlatformParameters
    Assert-PathExists $ServiceParameters
    Assert-PathExists $BackendDir

    if (-not (Test-Path -LiteralPath (Join-Path $BackendDir "mvnw.cmd"))) {
        throw "Expected Maven wrapper not found at '$BackendDir\\mvnw.cmd'."
    }

    # Fail fast if secrets/config placeholders were never replaced.
    $dataSecretOverrides = Get-DataSecretOverrides
    if ($dataSecretOverrides.Count -gt 0) {
        Write-Host "Using data stack secrets from environment variables." -ForegroundColor DarkCyan
    }
    if (-not $env:CARECONNECT_DATABASE_MASTER_PASSWORD) {
        throw "Missing CARECONNECT_DATABASE_MASTER_PASSWORD. Set it in this PowerShell session before running the deploy script."
    }
    if (-not $env:CARECONNECT_JWT_SECRET) {
        throw "Missing CARECONNECT_JWT_SECRET. Set it in this PowerShell session (at least 32 random characters) before running the deploy script."
    }
    if ($env:CARECONNECT_JWT_SECRET.Length -lt 32) {
        throw "CARECONNECT_JWT_SECRET must be at least 32 characters (current length: $($env:CARECONNECT_JWT_SECRET.Length))."
    }
    $script:DataEffectiveParameters = New-EffectiveParameterFile -BaseParameterFile $DataParameters -Overrides $dataSecretOverrides

    Test-PlaceholderValue -ParameterFile $script:DataEffectiveParameters -DisallowedFragments @("REPLACE_ME")
    Assert-ParameterMinLength -ParameterFile $script:DataEffectiveParameters -ParameterKey "DatabaseMasterPassword" -MinLength 8
    Assert-ParameterMinLength -ParameterFile $script:DataEffectiveParameters -ParameterKey "JwtSecret" -MinLength 32
    Assert-HealthCheckPathValue -ParameterFile $ServiceParameters
    Assert-PlatformRepositoryNameAvailable -ParameterFile $PlatformParameters

    Write-Step "Verifying AWS credentials for profile '$Profile'"
    $script:CurrentOperation = "Verifying AWS credentials"
    & aws sts get-caller-identity --profile $Profile --region $Region | Out-Null
    Assert-LastExitCode "AWS credential validation"

    # Stack order matters: networking -> data -> platform -> image push -> service.
    # Later stacks import values created by earlier ones.
    Write-Step "Deploying networking stack: $NetworkingStackName"
    Invoke-CloudFormationDeploy -StackName $NetworkingStackName -TemplatePath $NetworkingTemplate -ParameterFile $NetworkingParameters

    Write-Step "Deploying data stack: $DataStackName"
    Invoke-CloudFormationDeploy -StackName $DataStackName -TemplatePath $DataTemplate -ParameterFile $script:DataEffectiveParameters

    Write-Step "Deploying platform stack: $PlatformStackName"
    Invoke-CloudFormationDeploy -StackName $PlatformStackName -TemplatePath $PlatformTemplate -ParameterFile $PlatformParameters

    # The platform stack creates the ECR repository. We need that URI before the
    # Docker image can be tagged and pushed.
    Write-Step "Reading ECR repository URI"
    $script:CurrentOperation = "Reading ECR repository URI"
    $RepositoryUri = (Get-CloudFormationOutput -StackName $PlatformStackName -OutputKey "EcrRepositoryUri").Trim()
    if (-not $RepositoryUri) {
        throw "Platform stack did not return EcrRepositoryUri."
    }

    $RepositoryName = ($RepositoryUri -split "/", 2)[1]
    $ImageUri = "$RepositoryUri`:$ImageTag"
    $LocalImageName = "careconnect-backend-local:$ImageTag"

    # Package the backend as the Dockerfile expects: Spring Boot fat jar using
    # the docker Maven profile.
    Write-Step "Building backend jar"
    Push-Location $BackendDir
    try {
        $script:CurrentOperation = "Building backend jar"
        $mavenArgs = @("-B", "-ntp", "clean", "package", "-Pdocker")
        if (-not $RunTests) {
            $mavenArgs += "-DskipTests"
        }
        & .\mvnw.cmd @mavenArgs
        Assert-LastExitCode "Maven package build"

        # Authenticate Docker to the registry before push.
        Write-Step "Logging into ECR"
        $script:CurrentOperation = "Logging into ECR"
        $RegistryHost = ($RepositoryUri -split "/", 2)[0]
        $LoginPassword = & aws ecr get-login-password --profile $Profile --region $Region
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

    # The service stack is deployed last because it needs the final image URI.
    Write-Step "Deploying service stack: $ServiceStackName"
    $ServiceOverrides = @{
        BackendImageUri = $ImageUri
    }
    Invoke-CloudFormationDeploy -StackName $ServiceStackName -TemplatePath $ServiceTemplate -ParameterFile $ServiceParameters -Overrides $ServiceOverrides

    # Print the final API Gateway endpoint so the frontend or health checks can use it.
    Write-Step "Reading final API endpoint"
    $script:CurrentOperation = "Reading final API endpoint"
    $ApiEndpoint = (Get-CloudFormationOutput -StackName $ServiceStackName -OutputKey "ApiEndpoint").Trim()
    $script:CurrentStackName = $null
    $script:CurrentOperation = $null

    Write-Host ""
    Write-Host "Deployment complete." -ForegroundColor Green
    Write-Host "Environment:   $Environment"
    Write-Host "Repository:    $RepositoryName"
    Write-Host "Image URI:     $ImageUri"
    Write-Host "API Endpoint:  $ApiEndpoint"
    Write-Host "Health check:  $ApiEndpoint/v1/api/test/health"
    Write-Host "Elapsed time:  $(Get-ElapsedTimeText)"
}
catch {
    Write-Host ""
    Write-Host "Deployment failed." -ForegroundColor Red
    $errorMessage = if ($_.Exception.Message) { $_.Exception.Message } else { $_.ToString() }
    if ($errorMessage) {
        Write-Host $errorMessage -ForegroundColor Red
    }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message -ForegroundColor Red
    }
    Write-Host "Elapsed time: $(Get-ElapsedTimeText)" -ForegroundColor Yellow

    if ($null -ne $script:CurrentOperation -and $script:CurrentOperation) {
        Write-Host "Last operation: $script:CurrentOperation" -ForegroundColor Yellow
    }

    if ($null -ne $script:CurrentStackName -and $script:CurrentStackName) {
        Write-Host ""
        Write-Host "Troubleshoot this stack with:" -ForegroundColor Yellow
        Write-Host "aws cloudformation describe-stack-events --profile $Profile --region $Region --stack-name $script:CurrentStackName --query `"StackEvents[?contains(ResourceStatus, 'FAILED')].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]`" --output table" -ForegroundColor Yellow
    }

    exit 1
}
finally {
    foreach ($tempFile in $script:TemporaryFiles) {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    if ($script:HadNativePreference) {
        $global:PSNativeCommandUseErrorActionPreference = $script:OriginalNativePreference
    }
}
