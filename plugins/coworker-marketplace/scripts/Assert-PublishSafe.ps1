#Requires -Version 5.1
<#
.SYNOPSIS
  Fail if the coworker marketplace tree looks unsafe to publish.
#>
[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$failed = $false

function Write-Finding {
    param([string]$Severity, [string]$Path, [string]$Detail)
    Write-Host "[$Severity] $Path : $Detail"
    if ($Severity -eq 'FAIL') { $script:failed = $true }
}

$denyName = @(
    '\.env$',
    '\.pem$',
    '\.pfx$',
    'credentials',
    'client_secret',
    'settings\.json$',
    '\.local\.json$',
    'id_rsa',
    '\.cursor\\mcp\.json$'
)

$denyContent = @(
    '(?i)(api[_-]?key|secret|password|token)\s*[=:]\s*[''"][^''"]{8,}',
    '(?i)BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY',
    '(?i)\b(ghp_|github_pat_|sk-live-|sk-proj-|xox[baprs]-)[A-Za-z0-9_\-]{10,}',
    '(?i)IWUNET\\[^\\\s]+\\',
    '(?i)Bearer\s+[A-Za-z0-9\-._~+/]+=*'
)

$warnContent = @(
    '(?i)C:\\Users\\[^\\\s]+',
    '(?i)AppData\\(Roaming|Local)\\Cursor',
    '(?i)C:\\Projects\\'
)

Write-Host "Assert-PublishSafe root: $Root"
Write-Host ''

$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.Name -ne 'Assert-PublishSafe.ps1'
    }

foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/')
    foreach ($pat in $denyName) {
        if ($rel -match $pat -or $f.Name -match $pat) {
            Write-Finding -Severity 'FAIL' -Path $rel -Detail "Denied filename/path pattern: $pat"
        }
    }

    # Skip binary-ish by extension
    if ($f.Extension -match '^\.(png|jpg|jpeg|gif|webp|ico|pdf|zip|exe|dll)$') {
        continue
    }

    $text = $null
    try {
        $text = [System.IO.File]::ReadAllText($f.FullName)
    }
    catch {
        Write-Finding -Severity 'WARN' -Path $rel -Detail "Could not read as text: $($_.Exception.Message)"
        continue
    }

    foreach ($pat in $denyContent) {
        if ($text -match $pat) {
            Write-Finding -Severity 'FAIL' -Path $rel -Detail "Denied content pattern matched"
        }
    }
    foreach ($pat in $warnContent) {
        if ($text -match $pat) {
            Write-Finding -Severity 'WARN' -Path $rel -Detail "Machine-local path pattern matched (prefer placeholders)"
        }
    }
}

# Required layout for Cursor Team Marketplace import
$required = @(
    '.cursor-plugin\marketplace.json',
    'plugins\coworker-desk\.cursor-plugin\plugin.json',
    'plugins\tickets\.cursor-plugin\plugin.json',
    'plugins\codex\.cursor-plugin\plugin.json',
    'plugins\coworker-desk\skills\coworker-desk\SKILL.md',
    'plugins\tickets\skills\tickets\SKILL.md',
    'plugins\codex\skills\codex\SKILL.md'
)
foreach ($req in $required) {
    $p = Join-Path $Root $req
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Finding -Severity 'FAIL' -Path $req -Detail 'Required publish file missing'
    }
}

# Logos referenced by plugin.json
foreach ($plug in @('coworker-desk', 'tickets', 'codex')) {
    $pj = Join-Path $Root "plugins\$plug\.cursor-plugin\plugin.json"
    if (Test-Path -LiteralPath $pj) {
        $json = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json
        if ($json.logo) {
            $logoPath = Join-Path (Join-Path $Root "plugins\$plug") ($json.logo -replace '/', '\')
            if (-not (Test-Path -LiteralPath $logoPath)) {
                Write-Finding -Severity 'FAIL' -Path "plugins\$plug\$($json.logo)" -Detail 'plugin.json logo path missing'
            }
        }
    }
}

Write-Host ''
if ($failed) {
    Write-Host 'RESULT: FAIL - do not publish until findings are fixed.'
    exit 1
}

Write-Host 'RESULT: PASS - no deny findings. Review WARN lines if any, then push.'
exit 0
