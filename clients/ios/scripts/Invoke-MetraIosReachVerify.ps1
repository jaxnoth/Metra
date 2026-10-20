#Requires -Version 7.0
<#
.SYNOPSIS
    HQ gate before iOS device/simulator smoke: Serve + Vision Ask must be honest and reachable.
.DESCRIPTION
    Fails hard on:
      - Ops /api/meta unreachable
      - Tailscale Serve down when bindTailscale is on
      - Ask engine degraded (unless -AllowDegradedAuth for cursor_auth_error envelope-only check)
      - Vision Ask returning a PowerShell/ValidateSet mash (no Vision reason field)
      - Vision Ask answered without text
.NOTES
    Run from Metra root on the Ops host (jumpbox). Phone rebuild is useless while this is red.
#>
[CmdletBinding()]
param(
    [string]$OpsBaseUrl = '',
    [switch]$AllowDegradedAuth,
    [int]$AskTimeoutSec = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Resolve-MetraIosGateLocal.ps1')
$cfg = Resolve-MetraIosGateLocalSettings -OpsBaseUrl $OpsBaseUrl
$OpsBaseUrl = $cfg.OpsBaseUrl

function Write-Gate([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $mark = if ($Ok) { 'PASS' } else { 'FAIL' }
    if ($Detail) { Write-Host "[$mark] $Name - $Detail" } else { Write-Host "[$mark] $Name" }
    return $Ok
}

function Get-MetaProp([object]$Obj, [string]$Name, [string]$Default = '') {
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if (-not $p) { return $Default }
    $v = $p.Value
    if ($null -eq $v) { return $Default }
    return [string]$v
}

function Get-MetaPropBool([object]$Obj, [string]$Name, [bool]$Default = $false) {
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if (-not $p -or $null -eq $p.Value) { return $Default }
    try { return [bool]$p.Value } catch { return $Default }
}

$failures = [System.Collections.Generic.List[string]]::new()
$base = $OpsBaseUrl.Trim().TrimEnd('/')

# --- meta ---
$meta = $null
try {
    $metaResp = Invoke-WebRequest -Uri "$base/api/meta" -UseBasicParsing -TimeoutSec 15
    $meta = $metaResp.Content | ConvertFrom-Json
}
catch {
    [void](Write-Gate 'meta' $false $_.Exception.Message)
    Write-Host 'VERIFY_FAIL count=1 items=meta'
    exit 2
}

$bindTs = Get-MetaPropBool -Obj $meta -Name 'bindTailscale' -Default $false
$serveOk = Get-MetaPropBool -Obj $meta -Name 'serveOk' -Default $false
if ($bindTs -and -not $serveOk) {
    [void](Write-Gate 'serve' $false (Get-MetaProp -Obj $meta -Name 'serveError'))
    $failures.Add('serve')
}
else {
    [void](Write-Gate 'serve' $true "bindTailscale=$bindTs serveOk=$serveOk")
}

$ask = $null
$askProp = $meta.PSObject.Properties['askEngine']
if ($askProp) { $ask = $askProp.Value }
$degraded = Get-MetaProp -Obj $ask -Name 'degradedCode'
$askHealthy = Get-MetaPropBool -Obj $ask -Name 'healthy' -Default $false
$authDegraded = ($degraded -eq 'cursor_auth_error')
# AllowDegradedAuth must win before the unhealthy check (degraded engines are often healthy=false).
if ($authDegraded -and $AllowDegradedAuth) {
    [void](Write-Gate 'ask-engine' $true "degraded auth allowed for envelope check ($degraded)")
}
elseif (-not $askHealthy -or $degraded) {
    [void](Write-Gate 'ask-engine' $false "healthy=$askHealthy degradedCode=$degraded")
    $failures.Add('ask-engine')
}
else {
    $engineName = Get-MetaProp -Obj $ask -Name 'engine' -Default 'unknown'
    [void](Write-Gate 'ask-engine' $true "engine=$engineName")
}

# --- vision ask ---
$turnId = 'verify-{0}' -f [guid]::NewGuid().ToString('n').Substring(0, 8)
$bodyObj = [ordered]@{
    contractVersion = '1'
    mode            = 'vision'
    surface         = 'ios'
    intent          = 'relational'
    posture         = 'Company'
    message         = 'Reply with exactly: ios-reach-ok'
    conversationId  = 'ios-reach-verify'
    turnId          = $turnId
    capabilities    = @{
        localAssistAvailable = $false
        durableWritesAllowed = $false
    }
    context         = @{
        client            = 'ops-ios'
        personalityWanted = $true
        inputModality     = 'text'
        teachingWanted    = $false
    }
}
$body = $bodyObj | ConvertTo-Json -Depth 6 -Compress

$visionJson = $null
$statusCode = 0
$rawBody = ''
try {
    $visionResp = Invoke-WebRequest -Uri "$base/api/ask" -Method POST -Body $body `
        -ContentType 'application/json; charset=utf-8' `
        -Headers @{ 'X-Metra-Client' = 'ops-ios'; 'X-Metra-Device' = 'ios-reach-verify' } `
        -UseBasicParsing -TimeoutSec $AskTimeoutSec
    $statusCode = [int]$visionResp.StatusCode
    $rawBody = [string]$visionResp.Content
    try { $visionJson = $rawBody | ConvertFrom-Json } catch { $visionJson = $null }
}
catch {
    $ex = $_.Exception
    $resp = $ex.Response
    if ($resp -is [System.Net.Http.HttpResponseMessage]) {
        $statusCode = [int]$resp.StatusCode
        if ($null -ne $resp.Content) {
            $rawBody = [string]$resp.Content.ReadAsStringAsync().Result
        }
        else {
            $rawBody = ''
        }
        try { $visionJson = $rawBody | ConvertFrom-Json } catch { $visionJson = $null }
    }
    else {
        [void](Write-Gate 'vision-ask' $false $ex.Message)
        $failures.Add('vision-ask')
    }
}

if ($null -eq $visionJson) {
    # Record even when earlier stages failed (serve/ask-engine) so HQ diagnostics stay complete.
    if (-not $failures.Contains('vision-ask')) {
        $preview = if ($rawBody.Length -gt 0) { $rawBody.Substring(0, [Math]::Min(200, $rawBody.Length)) } else { '(empty body)' }
        [void](Write-Gate 'vision-ask' $false "HTTP $statusCode non-JSON or empty: $preview")
        $failures.Add('vision-ask')
    }
}
elseif ($visionJson) {
    $reason = Get-MetaProp $visionJson 'reason'
    $status = Get-MetaProp $visionJson 'status'
    $errText = Get-MetaProp $visionJson 'error'
    $hasContract = (Get-MetaProp $visionJson 'contractVersion') -eq '1'
    $detail = Get-MetaProp $visionJson 'detail'

    if ($errText -match 'ValidateSet|Cannot validate argument on parameter' -or $rawBody -match 'ValidateSet') {
        [void](Write-Gate 'vision-envelope' $false "PowerShell ValidateSet leak: $errText")
        $failures.Add('vision-envelope')
    }
    elseif (-not $hasContract) {
        [void](Write-Gate 'vision-envelope' $false 'Missing or invalid Vision contractVersion (expected 1)')
        $failures.Add('vision-envelope')
    }
    elseif ($status -eq 'answered') {
        $text = ''
        $resp = $visionJson.PSObject.Properties['response']
        if ($resp -and $resp.Value -and $resp.Value.PSObject.Properties['text']) {
            $text = [string]$resp.Value.text
        }
        if (-not $text) { $text = Get-MetaProp $visionJson 'message' }
        if ([string]::IsNullOrWhiteSpace($text)) {
            [void](Write-Gate 'vision-ask' $false 'answered with empty text')
            $failures.Add('vision-ask')
        }
        else {
            $preview = $text.Substring(0, [Math]::Min(60, $text.Length))
            [void](Write-Gate 'vision-ask' $true "HTTP $statusCode answered ($preview)")
        }
    }
    elseif ($status -eq 'unavailable') {
        # Fail closed: honest envelopes still mean Ask/Vision is not working for the phone path.
        # Only -AllowDegradedAuth + cursor_auth_error may pass (envelope-shape check while key is missing).
        if ($reason -eq 'cursor_auth_error' -and $AllowDegradedAuth) {
            [void](Write-Gate 'vision-ask' $true "HTTP $statusCode unavailable reason=$reason (AllowDegradedAuth)")
        }
        elseif ($reason -eq 'cursor_auth_error') {
            [void](Write-Gate 'vision-ask' $false "honest auth fail ($reason) - run: .\metra.ps1 ask key set <key>")
            $failures.Add('vision-ask-auth')
        }
        else {
            [void](Write-Gate 'vision-ask' $false "unavailable reason=$reason detail=$detail")
            $failures.Add('vision-ask')
        }
    }
    else {
        [void](Write-Gate 'vision-ask' $false "unexpected status=$status reason=$reason HTTP $statusCode")
        $failures.Add('vision-ask')
    }
}

if ($failures.Count -gt 0) {
    Write-Host "VERIFY_FAIL count=$($failures.Count) items=$($failures -join ',')"
    Write-Host 'Next: fix Ask/Serve on HQ before phone rebuild. Auth: .\metra.ps1 ask key set <CURSOR_API_KEY>'
    exit 1
}

Write-Host 'VERIFY_OK'
exit 0
