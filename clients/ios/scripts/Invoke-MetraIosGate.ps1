#Requires -Version 7.0
<#
.SYNOPSIS
    Formal iOS companion verify: HQ Reach first, then optional Mac sim / device prove.
.DESCRIPTION
    Non-UI failures (Serve, Ask engine, Vision envelope) must fail here - never on the phone.

    Gate order (fail-closed):
      1. Reach  - Invoke-MetraIosReachVerify.ps1 (this host / Ops URL)
      2. Sim    - SSH Mac Invoke-MetraIosSimSmoke.sh (-SimSmoke)
      3. Device - Mac GUI Terminal ~/prove-metra (-DeviceProve via osascript)

    Default is Reach only. Pass -SimSmoke / -DeviceProve after Reach is green.
.EXAMPLE
    pwsh -File .\clients\ios\scripts\Invoke-MetraIosGate.ps1
.EXAMPLE
    pwsh -File .\clients\ios\scripts\Invoke-MetraIosGate.ps1 -SimSmoke -DeviceProve
#>
[CmdletBinding()]
param(
    [string]$OpsBaseUrl = 'https://jumpbox.emerald-banana.ts.net',
    [switch]$AllowDegradedAuth,
    [switch]$SimSmoke,
    [switch]$DeviceProve,
    [string]$MacSsh = 'stephen.swan@100.101.163.18',
    [string]$MacIosRoot = '~/Developer/Metra/clients/ios',
    [int]$AskTimeoutSec = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$reachScript = Join-Path $scriptDir 'Invoke-MetraIosReachVerify.ps1'
if (-not (Test-Path -LiteralPath $reachScript)) {
    Write-Host "Missing reach script: $reachScript"
    exit 2
}

# Reject shell metacharacters in remote path (interpolated into zsh -lc).
if ($MacIosRoot -notmatch '^[~A-Za-z0-9_./-]+$') {
    Write-Host "GATE_FAIL invalid MacIosRoot (allowed: ~ letters digits _ . / -)"
    exit 2
}

Write-Host '=== Metra iOS gate: Reach ==='
# Out-of-process so $LASTEXITCODE reflects the reach script (in-process & does not).
$reachArgList = [System.Collections.Generic.List[string]]::new()
[void]$reachArgList.AddRange([string[]]@(
        '-NoProfile', '-File', $reachScript,
        '-OpsBaseUrl', $OpsBaseUrl,
        '-AskTimeoutSec', "$AskTimeoutSec"
    ))
if ($AllowDegradedAuth) { [void]$reachArgList.Add('-AllowDegradedAuth') }
# Use the running PowerShell 7 binary path (cross-platform; do not invent a Windows-only filename under $PSHOME).
$pwsh = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($pwsh) -or -not (Test-Path -LiteralPath $pwsh)) {
    Write-Host 'GATE_FAIL could not resolve current PowerShell executable path'
    exit 2
}
& $pwsh @($reachArgList.ToArray())
$reachCode = $LASTEXITCODE
if ($reachCode -ne 0) {
    Write-Host 'GATE_FAIL stage=reach - fix Ops/Ask on HQ before sim or device.'
    exit $(if ($reachCode -gt 0) { $reachCode } else { 1 })
}
Write-Host 'GATE_PASS stage=reach'

if (-not $SimSmoke -and -not $DeviceProve) {
    Write-Host 'GATE_OK reach-only (pass -SimSmoke / -DeviceProve for Mac stages)'
    exit 0
}

function Invoke-MetraIosMacRemote {
    param(
        [Parameter(Mandatory)][string]$RemoteCommand,
        [Parameter(Mandatory)][string]$Stage
    )
    Write-Host "=== Metra iOS gate: $Stage ($MacSsh) ==="
    # Normalize to LF - Windows CRLF breaks remote `set -o pipefail`.
    $remote = ($RemoteCommand -replace "`r`n", "`n" -replace "`r", "`n").Trim()
    if ($MacSsh -match '^\s*-' -or $MacSsh -notmatch '^[A-Za-z0-9._@%-]+$') {
        Write-Host "GATE_FAIL invalid MacSsh (expected user@host, no leading dash / metacharacters)"
        exit 2
    }
    $sshArgs = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=20',
        '-o', 'StrictHostKeyChecking=accept-new',
        '--',
        $MacSsh,
        # Mac scripts are zsh; HQ sshd default shell may be bash.
        "zsh -lc $($remote | ConvertTo-Json -Compress)"
    )
    $out = & ssh @sshArgs 2>&1
    $code = $LASTEXITCODE
    if ($out) { $out | ForEach-Object { Write-Host $_ } }
    if ($code -ne 0) {
        Write-Host "GATE_FAIL stage=$Stage exit=$code"
        exit $(if ($code -gt 0) { $code } else { 1 })
    }
}

# Expand ~/ via $HOME on the Mac (quoted ~ does not expand). Paths already allowlist-validated.
if ($MacIosRoot -eq '~') {
    $remoteDir = '"$HOME"'
    $remoteProveScript = '"$HOME/scripts/run-prove-in-terminal.applescript"'
}
elseif ($MacIosRoot.StartsWith('~/')) {
    $rest = $MacIosRoot.Substring(2) -replace '\\', '/'
    $remoteDir = '"$HOME/' + $rest + '"'
    $remoteProveScript = '"$HOME/' + $rest + '/scripts/run-prove-in-terminal.applescript"'
}
else {
    $norm = $MacIosRoot -replace '\\', '/'
    $remoteDir = '"' + $norm + '"'
    $remoteProveScript = '"' + $norm + '/scripts/run-prove-in-terminal.applescript"'
}

if ($SimSmoke) {
    $simCmd = "cd $remoteDir && chmod +x scripts/Invoke-MetraIosSimSmoke.sh && ./scripts/Invoke-MetraIosSimSmoke.sh"
    Invoke-MetraIosMacRemote -RemoteCommand $simCmd -Stage 'sim-smoke'
    Write-Host 'GATE_PASS stage=sim-smoke'
}

if ($DeviceProve) {
    # Prefer GUI Terminal so codesign uses the unlocked login keychain.
    # && so osascript failure fails the gate (semicolon would mask with echo).
    $kick = "osascript $remoteProveScript && echo DEVICE_PROVE_KICKED"
    Invoke-MetraIosMacRemote -RemoteCommand $kick -Stage 'device-prove-kick'
    Write-Host 'GATE_PASS stage=device-prove-kick'
    Write-Host 'Watch Mac Terminal / ~/Library/Logs/MetraCompanion/weekly-reinstall.log for BUILD SUCCEEDED + install finished.'
    Write-Host 'Then unlock the phone, Trust developer if prompted, launch Metra, smoke text Ask (UI only).'
}

Write-Host 'GATE_OK'
exit 0
