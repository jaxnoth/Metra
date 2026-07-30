# Metra sessionStart: refresh Ops board when canvas snapshot is stale.
# Fail open - never block chat. Never runs meta.ps1 workspace.
$ErrorActionPreference = 'Stop'

try {
    $inputJson = [Console]::In.ReadToEnd()
    $null = $inputJson

    $metaRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $metaPs1 = Join-Path $metaRoot 'meta.ps1'
    if (-not (Test-Path -LiteralPath $metaPs1)) {
        Write-Output '{ "additional_context": "Metra sessionStart: meta.ps1 not found; skipped snapshot." }'
        exit 0
    }

    Import-Module (Join-Path $metaRoot 'scripts\Meta.psm1') -Force
    $stale = Test-MetaCanvasSnapshotStale -MaxAgeHours 4
    if (-not $stale) {
        Write-Output '{ "additional_context": "Metra Ops snapshot is fresh; skipped refresh." }'
        exit 0
    }

    $result = Export-MetaCanvasSnapshot -Quick
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
