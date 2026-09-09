# Metra capability bind ledger - Ask sessionId -> active capability car.
# Generic (not Narrative-specific). Machine-local under capability-bind/.

function Test-MetraCapabilityBindSessionId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$SessionId)
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $false }
    $s = $SessionId.Trim()
    if ($s.Length -lt 8 -or $s.Length -gt 128) { return $false }
    return ($s -match '^[A-Za-z0-9_-]+$')
}

function Get-MetraCapabilityBindRoot {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $data = Get-MetraMachineDataRoot -MetraRoot $MetraRoot
    $path = Join-Path $data 'capability-bind'
    [void][System.IO.Directory]::CreateDirectory($path)
    return $path
}

function Get-MetraCapabilityBindPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if (-not (Test-MetraCapabilityBindSessionId -SessionId $SessionId)) {
        throw "Invalid capability bind session id (expected 8-128 alphanumeric/underscore/hyphen)."
    }
    $safe = $SessionId.Trim()
    return (Join-Path (Get-MetraCapabilityBindRoot -MetraRoot $MetraRoot) "$safe.json")
}

function ConvertTo-MetraCapabilityBindRecord {
    <#
    .SYNOPSIS
        Normalize bind JSON (maps legacy engineSessionId to runtimeSessionId).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Object)
    $cap = [string](Get-MetraProp -Object $Object -Name 'capability' -Default '')
    if ([string]::IsNullOrWhiteSpace($cap)) { return $null }
    $runtime = [string](Get-MetraProp -Object $Object -Name 'runtimeSessionId' -Default '')
    if ([string]::IsNullOrWhiteSpace($runtime)) {
        $runtime = [string](Get-MetraProp -Object $Object -Name 'engineSessionId' -Default '')
    }
    return [PSCustomObject]@{
        capability          = $cap
        runtimeSessionId    = $runtime
        packId              = Get-MetraProp -Object $Object -Name 'packId' -Default $null
        boundAt             = [string](Get-MetraProp -Object $Object -Name 'boundAt' -Default '')
        lastTouchedAt       = [string](Get-MetraProp -Object $Object -Name 'lastTouchedAt' -Default '')
        pendingLeaveConfirm = Get-MetraProp -Object $Object -Name 'pendingLeaveConfirm' -Default $null
    }
}

function Get-MetraCapabilityBind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if (-not (Test-MetraCapabilityBindSessionId -SessionId $SessionId)) {
        return $null
    }
    $path = Get-MetraCapabilityBindPath -SessionId $SessionId -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($path)
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) { return $null }
        return ConvertTo-MetraCapabilityBindRecord -Object $obj
    }
    catch {
        return $null
    }
}

function Set-MetraCapabilityBind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$Capability,
        [Parameter(Mandatory)][string]$RuntimeSessionId,
        [string]$PackId = '',
        [object]$PendingLeaveConfirm = $null,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if (-not (Test-MetraCapabilityBindSessionId -SessionId $SessionId)) {
        throw "Invalid capability bind session id."
    }
    $cap = $Capability.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($cap) -or $cap.Length -gt 64 -or $cap -notmatch '^[a-z][a-z0-9_-]*$') {
        throw "Invalid capability name."
    }
    if ([string]::IsNullOrWhiteSpace($RuntimeSessionId)) {
        throw "runtimeSessionId required."
    }
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $existing = Get-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot
    $boundAt = $now
    if ($null -ne $existing) {
        $prev = [string](Get-MetraProp -Object $existing -Name 'boundAt' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($prev)) { $boundAt = $prev }
    }
    $rec = [ordered]@{
        capability          = $cap
        runtimeSessionId    = $RuntimeSessionId.Trim()
        packId              = $(if ([string]::IsNullOrWhiteSpace($PackId)) { $null } else { $PackId.Trim() })
        boundAt             = $boundAt
        lastTouchedAt       = $now
        pendingLeaveConfirm = $PendingLeaveConfirm
    }
    $path = Get-MetraCapabilityBindPath -SessionId $SessionId -MetraRoot $MetraRoot
    $json = ($rec | ConvertTo-Json -Depth 8 -Compress)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $json, $utf8)
    return Get-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot
}

function Update-MetraCapabilityBindTouch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [object]$PendingLeaveConfirm,
        [switch]$ClearPendingLeave,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $bind = Get-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot
    if ($null -eq $bind) { return $null }
    $pending = Get-MetraProp -Object $bind -Name 'pendingLeaveConfirm' -Default $null
    if ($ClearPendingLeave) {
        $pending = $null
    }
    elseif ($PSBoundParameters.ContainsKey('PendingLeaveConfirm')) {
        $pending = $PendingLeaveConfirm
    }
    return Set-MetraCapabilityBind `
        -SessionId $SessionId `
        -Capability ([string]$bind.capability) `
        -RuntimeSessionId ([string]$bind.runtimeSessionId) `
        -PackId ([string](Get-MetraProp -Object $bind -Name 'packId' -Default '')) `
        -PendingLeaveConfirm $pending `
        -MetraRoot $MetraRoot
}

function Clear-MetraCapabilityBind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if (-not (Test-MetraCapabilityBindSessionId -SessionId $SessionId)) {
        return $false
    }
    $path = Get-MetraCapabilityBindPath -SessionId $SessionId -MetraRoot $MetraRoot
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $true
    }
    return $false
}
