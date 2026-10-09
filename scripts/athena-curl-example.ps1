# scripts/athena-curl-example.ps1
# Minimal working athenahealth PREVIEW example: 2-legged token, then a Patient search.
# Windows counterpart of athena-curl-example.sh. Requires curl.exe (ships with Windows 10 1803+).
#
# PowerShell notes that matter here:
#   - curl.exe, NOT curl: in Windows PowerShell 5.1 `curl` is an alias for Invoke-WebRequest.
#   - "${id}:${secret}", NOT "$id:$secret": PowerShell reads `$id:` as a scope qualifier.
#   - Single-quote the URL: `&` is a reserved operator and a stray quote inside the value
#     produces a confusing 403 "invalid _count parameter".

$ErrorActionPreference = 'Stop'

$clientId     = 'PASTE_CLIENT_ID_HERE'
$clientSecret = 'PASTE_CLIENT_SECRET_HERE'

$host_    = 'https://api.preview.platform.athenahealth.com'
$practice = 'a-1.Practice-195900'

# --- 1. token ---------------------------------------------------------------
$tokenJson = curl.exe -sS -X POST "$host_/oauth2/v1/token" `
  -u "${clientId}:${clientSecret}" `
  -H 'Content-Type: application/x-www-form-urlencoded' `
  -H 'Accept: application/json' `
  -d 'grant_type=client_credentials' `
  --data-urlencode 'scope=system/Patient.read' | Out-String | ConvertFrom-Json

if (-not $tokenJson.access_token) {
    Write-Error "Token request failed: $($tokenJson | ConvertTo-Json -Compress)"
}
$token = $tokenJson.access_token

# --- 2. query ---------------------------------------------------------------
# ah-practice is REQUIRED on every call. Patient search also requires one of
# [_id] [identifier] [name] [family,birthdate] [family,gender] [family,given].
# -G with --data-urlencode avoids one long quoted URL entirely.
$bundle = curl.exe -sS -G "$host_/fhir/r4/Patient" `
  -H "Authorization: Bearer $token" `
  -H 'Accept: application/json' `
  --data-urlencode "ah-practice=$practice" `
  --data-urlencode 'family=Smith' `
  --data-urlencode 'gender=female' `
  --data-urlencode '_count=5' | Out-String | ConvertFrom-Json

# Filter out OperationOutcome entries: athena reports an over-broad query as HTTP 200 with a
# fatal "too-costly" OperationOutcome inside Bundle.entry, not as a 4xx.
$bundle.entry |
  Where-Object { $_.search.mode -ne 'outcome' } |
  ForEach-Object {
      [pscustomobject]@{
          id        = $_.resource.id
          name      = "$($_.resource.name[0].family), $($_.resource.name[0].given[0])"
          birthDate = $_.resource.birthDate
          gender    = $_.resource.gender
      }
  } | Format-Table -AutoSize
