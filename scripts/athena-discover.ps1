# scripts/athena-discover.ps1
#
# Discovery probe against the athenahealth PREVIEW sandbox using 2-legged
# (client_credentials) OAuth. Windows counterpart of athena-discover.sh.
# Saves every response under backend/core/src/test/resources/athena/ so the output doubles
# as the test fixture set. Run by hand, never in CI. Requires curl.exe.
#
# Facts baked in from a live run against practice 195900:
#   - OAuth at /oauth2/v1/*, FHIR R4 at /fhir/r4 (no practice path segment).
#   - ah-practice is a required SEARCH PARAMETER, format a-1.Practice-NNNNNN.
#   - The token endpoint quota is tighter than the API rate limit; three rapid requests
#     returned 429. This script makes exactly ONE token request.
#   - An unconfigured scope fails the whole token request with 400 "Invalid Scope".
#   - A query estimated over 1000 results returns HTTP 200 with a fatal "too-costly"
#     OperationOutcome INSIDE Bundle.entry, so entries are filtered on search.mode.
#
# Usage:
#   $env:ATHENA_CLIENT_ID='...'; $env:ATHENA_CLIENT_SECRET='...'
#   $env:ATHENA_PRACTICE_ID='a-1.Practice-195900'   # the preview sandbox practice
#   .\scripts\athena-discover.ps1

$ErrorActionPreference = 'Stop'

if (-not $env:ATHENA_CLIENT_ID)     { Write-Error 'set $env:ATHENA_CLIENT_ID' }
if (-not $env:ATHENA_CLIENT_SECRET) { Write-Error 'set $env:ATHENA_CLIENT_SECRET' }
# No default: ATHENA_ENV=production is allowed, and a sandbox fallback would then be sent there silently.
if (-not $env:ATHENA_PRACTICE_ID)   { Write-Error 'set $env:ATHENA_PRACTICE_ID (preview sandbox: a-1.Practice-195900)' }

$clientId     = $env:ATHENA_CLIENT_ID
$clientSecret = $env:ATHENA_CLIENT_SECRET
$practice     = $env:ATHENA_PRACTICE_ID
$scopes       = if ($env:ATHENA_SCOPES)      { $env:ATHENA_SCOPES }      else { 'system/Patient.read' }
$envName      = if ($env:ATHENA_ENV)         { $env:ATHENA_ENV }         else { 'preview' }

$apiHost = if ($envName -eq 'production') {
    'https://api.platform.athenahealth.com'
} else {
    'https://api.preview.platform.athenahealth.com'
}
$fhir = "$apiHost/fhir/r4"

$repoRoot = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repoRoot 'backend/core/src/test/resources/athena'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Save-Json($obj, $name) {
    $obj | ConvertTo-Json -Depth 40 | Set-Content -Path (Join-Path $out $name) -Encoding utf8
}
function Write-Rule { Write-Host ('-' * 60) }

Write-Rule; Write-Host 'STEP 1: token (ONE request; the endpoint quota is tight)'; Write-Rule
$tokenJson = curl.exe -sS -X POST "$apiHost/oauth2/v1/token" `
  -u "${clientId}:${clientSecret}" `
  -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' `
  -d 'grant_type=client_credentials' --data-urlencode "scope=$scopes" | Out-String | ConvertFrom-Json

if (-not $tokenJson.access_token) {
    Write-Host ($tokenJson | ConvertTo-Json -Depth 10)
    Write-Host ''
    Write-Host '  "Invalid Scope"  -> a scope in ATHENA_SCOPES is not configured on the portal app.'
    Write-Host '  "invalid_client" -> wrong secret, or the app is not enabled for this environment.'
    Write-Host '  "Quota Exceeded" -> token endpoint quota; wait and retry.'
    Write-Error 'Token request failed.'
}
$token = $tokenJson.access_token
Write-Host "access_token acquired (len $($token.Length)), expires_in $($tokenJson.expires_in)s"
Write-Host 'GRANTED scope (this, not ATHENA_SCOPES, drives which resource types you can sync):'
$tokenJson.scope -split ' ' | ForEach-Object { Write-Host "  $_" }

# Never leave a live bearer token in a committed fixture.
$tokenJson.access_token = 'REDACTED_FOR_FIXTURE'
Save-Json $tokenJson 'token-response.json'

$auth = @('-H', "Authorization: Bearer $token", '-H', 'Accept: application/json')

Write-Rule; Write-Host 'STEP 2: CapabilityStatement'; Write-Rule
$cap = curl.exe -sS @auth "$fhir/metadata" | Out-String | ConvertFrom-Json
Save-Json $cap 'CapabilityStatement.json'
$types = ($cap.rest.resource.type | Sort-Object) -join ' '
Write-Host "Supported resource types:`n  $types"
Write-Host 'Required search-param combinations per type:'
foreach ($r in $cap.rest.resource) {
    $combos = @()
    foreach ($e in $r.extension) {
        if ($e.url -like '*ah-search-parameter-metadata*') {
            $combos += ($e.extension | Where-Object { $_.url -eq 'requiredAnySearchParams' }).valueString
        }
    }
    if ($combos.Count -gt 0) { Write-Host ("  {0}: {1}" -f $r.type, ($combos -join ' | ')) }
}

Write-Rule; Write-Host 'STEP 3: SMART configuration'; Write-Rule
$smart = curl.exe -sS @auth "$fhir/.well-known/smart-configuration" | Out-String | ConvertFrom-Json
Save-Json $smart 'smart-configuration.json'
$smart.PSObject.Properties | Where-Object { $_.Name -like '*endpoint*' } |
    ForEach-Object { Write-Host "  $($_.Name): $($_.Value)" }

Write-Rule; Write-Host 'STEP 4: patients (search needs a valid param combination)'; Write-Rule
$found = $null
foreach ($q in @('family=Smith&gender=female', 'name=Testpatient')) {
    $b = curl.exe -sS @auth "$fhir/Patient?ah-practice=$practice&$q&_count=5" | Out-String | ConvertFrom-Json
    $real = @($b.entry | Where-Object { $_.search.mode -ne 'outcome' })
    $oc   = @($b.entry | Where-Object { $_.search.mode -eq 'outcome' })
    Write-Host ("  {0,-34} patients={1}{2}" -f $q, $real.Count,
        $(if ($oc.Count) { "  [outcome: $($oc[0].resource.issue[0].code)]" } else { '' }))
    if ($real.Count -gt 0 -and -not $found) { $found = $b; Save-Json $b 'Patient-searchset.json' }
}

if ($found) {
    Write-Host "`nPatients found:"
    $found.entry | Where-Object { $_.search.mode -ne 'outcome' } | ForEach-Object {
        Write-Host ("  {0}  {1}, {2}  dob={3}  {4}" -f $_.resource.id,
            $_.resource.name[0].family, $_.resource.name[0].given[0],
            $_.resource.birthDate, $_.resource.gender)
    }
    $pid_ = (@($found.entry | Where-Object { $_.search.mode -ne 'outcome' })[0]).resource.id

    Write-Rule; Write-Host "STEP 5: per-resource pull for $pid_ (403 = scope not granted)"; Write-Rule
    # MedicationRequest requires patient AND intent together; patient alone is a 403.
    $plan = [ordered]@{
        'Condition' = ''; 'Observation' = ''; 'AllergyIntolerance' = ''
        'MedicationRequest' = '&intent=order'; 'MedicationStatement' = ''
        'Immunization' = ''; 'Procedure' = ''; 'DocumentReference' = ''
        'DiagnosticReport' = ''; 'Encounter' = ''
    }
    foreach ($rt in $plan.Keys) {
        $url = "$fhir/$($rt)?ah-practice=$practice&patient=$pid_$($plan[$rt])&_count=5"
        $code = curl.exe -sS -o "$env:TEMP\ath.json" -w '%{http_code}' @auth $url
        if ($code -eq '200') {
            $b = Get-Content "$env:TEMP\ath.json" -Raw | ConvertFrom-Json
            $n = @($b.entry | Where-Object { $_.search.mode -ne 'outcome' }).Count
            if ($n -gt 0) { Save-Json $b "$rt-searchset.json" }
            Write-Host ("  {0,-22} {1,-6} {2}" -f $rt, $code, $n)
        } else {
            Write-Host ("  {0,-22} {1,-6} (not saved)" -f $rt, $code)
        }
    }
}

Write-Rule; Write-Host "Fixtures in $out :"
Get-ChildItem $out | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host 'Scrub before committing. Never point this at production.'
