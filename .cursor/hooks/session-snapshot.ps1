# Metra sessionStart: refresh Ops board when canvas snapshot is stale.
# Fail open - never block chat. Never runs metra.ps1 workspace.
$ErrorActionPreference = 'Stop'

try {
    $inputJson = [Console]::In.ReadToEnd()
    $null = $inputJson

    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $metraPs1 = Join-Path $metraRoot 'metra.ps1'
    if (-not (Test-Path -LiteralPath $metraPs1)) {
        Write-Output '{ "additional_context": "Metra sessionStart: metra.ps1 not found; skipped snapshot." }'
        exit 0
    }

    Import-Module (Join-Path $metraRoot 'scripts\Metra.psm1') -Force
    $stale = Test-MetraCanvasSnapshotStale -MaxAgeHours 4
    if (-not $stale) {
        Write-Output '{ "additional_context": "Metra Ops snapshot is fresh; skipped refresh." }'
        exit 0
    }

    $result = Export-MetraCanvasSnapshot -Quick
    $msg = "Metra Ops snapshot refreshed (quick). Projects=$($result.ProjectCount); driftSignals=$($result.DriftCount); todos=$($result.TodoCount)."
    $payload = @{ additional_context = $msg } | ConvertTo-Json -Compress
    Write-Output $payload
    exit 0
}
catch {
    $err = ($_ | Out-String).Trim() -replace '[\r\n]+', ' '
    if ($err.Length -gt 240) { $err = $err.Substring(0, 240) + '...' }
    $payload = @{ additional_context = "Metra sessionStart snapshot failed (fail-open): $err" } | ConvertTo-Json -Compress
    Write-Output $payload
    exit 0
}

