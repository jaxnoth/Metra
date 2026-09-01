# Metra host adapters for Loom. Domain code calls these only — never scripts/private/*.ps1.

function Get-LoomHostRoot {
    [CmdletBinding()]
    param()
    if ($script:LoomHostRootOverride) {
        return [System.IO.Path]::GetFullPath([string]$script:LoomHostRootOverride)
    }
    $cmd = Get-Command Get-MetraRoot -ErrorAction SilentlyContinue
    if ($cmd) {
        return & $cmd
    }
    # Standalone fallback: module lives at <metra>/modules/Loom
    $modRoot = $PSScriptRoot
    while ($modRoot -and (Split-Path -Leaf $modRoot) -ne 'Loom') {
        $modRoot = Split-Path -Parent $modRoot
    }
    if ($modRoot) {
        $candidate = Split-Path -Parent (Split-Path -Parent $modRoot)
        if (Test-Path -LiteralPath (Join-Path $candidate 'metra.ps1')) {
            return $candidate
        }
    }
    throw 'Loom host root unavailable (Metra not loaded and metra.ps1 not found).'
}

function Get-LoomInspectPlanRoots {
    [CmdletBinding()]
    param(
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-LoomHostRoot
    }
    $cmd = Get-Command Get-MetraInspectPlanRoots -ErrorAction SilentlyContinue
    if ($cmd) {
        return @(& $cmd -MetraRoot $MetraRoot)
    }
    # Isolation fallback: Cursor plans + docs
    $roots = New-Object System.Collections.Generic.List[string]
    $cursor = Join-Path $env:USERPROFILE '.cursor\plans'
    if (Test-Path -LiteralPath $cursor) { [void]$roots.Add($cursor) }
    $docs = Join-Path $MetraRoot 'docs'
    if (Test-Path -LiteralPath $docs) { [void]$roots.Add($docs) }
    return @($roots)
}

function Test-LoomRoutingAdapterAvailable {
    [CmdletBinding()]
    param()
    return $null -ne (Get-Command Get-MetraRoutingAmbiguity -ErrorAction SilentlyContinue)
}

function Test-LoomCaptureAdapterAvailable {
    [CmdletBinding()]
    param()
    return $null -ne (Get-Command Get-MetraCaptureLedger -ErrorAction SilentlyContinue)
}

function Get-LoomRoutingAmbiguity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [switch]$SkipTelemetry
    )
    if (-not (Test-LoomRoutingAdapterAvailable)) {
        return [PSCustomObject]@{
            Primary   = $null
            Ambiguous = $true
            Mode      = 'adapter-unavailable'
        }
    }
    return & (Get-Command Get-MetraRoutingAmbiguity) -Query $Query -SkipTelemetry:$SkipTelemetry
}

function Get-LoomCaptureLedger {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [int]$Limit = 40,
        [string]$Status = 'candidate'
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-LoomHostRoot
    }
    if (-not (Test-LoomCaptureAdapterAvailable)) {
        return @()
    }
    return @(& (Get-Command Get-MetraCaptureLedger) -MetraRoot $MetraRoot -Limit $Limit -Status $Status)
}

function Get-LoomRoutingContext {
    <#
    .SYNOPSIS
        Adapter: routing-context.result shape (Contracts/v1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request
    )
    $query = [string](Get-LoomProp -Object $Request -Name 'query' -Default '')
    $planPath = [string](Get-LoomProp -Object $Request -Name 'planPath' -Default '')
    $min = 0.85
    if (-not [string]::IsNullOrWhiteSpace($planPath) -and (Test-Path -LiteralPath $planPath)) {
        $hostRoot = Get-LoomHostRoot
        if (Test-LoomPathWithinRoot -Path $planPath -Root $hostRoot) {
            $fromPlan = [PSCustomObject]@{
                schemaVersion       = 1
                registryName        = 'Metra'
                root                = $hostRoot
                routingConfidence   = 0.99
                routingEvidence     = 'plan-path-under-metra-root'
                minimumConfidence   = $min
                eligible            = $true
            }
            Test-LoomContract -Schema 'routing-context.result' -Object $fromPlan | Out-Null
            return $fromPlan
        }
    }
    $amb = Get-LoomRoutingAmbiguity -Query $(if ($query) { $query } else { $planPath }) -SkipTelemetry
    if ($amb.Mode -eq 'adapter-unavailable') {
        $invalid = [PSCustomObject]@{
            schemaVersion     = 1
            registryName      = ''
            root              = ''
            routingConfidence = 0.0
            routingEvidence   = 'adapter-unavailable'
            minimumConfidence = $min
            eligible          = $false
        }
        Test-LoomContract -Schema 'routing-context.result' -Object $invalid | Out-Null
        return $invalid
    }
    if ($amb.Primary) {
        $score = [int]$amb.Primary.Score
        $conf = if ($score -ge 2) { 0.90 } elseif ($score -eq 1) { 0.75 } else { 0.50 }
        $resolved = [PSCustomObject]@{
            schemaVersion     = 1
            registryName      = [string]$amb.Primary.Name
            root              = [string]$amb.Primary.Root
            routingConfidence = $conf
            routingEvidence   = 'routing-ambiguity-primary'
            minimumConfidence = $min
            eligible          = ($conf -ge $min)
        }
        Test-LoomContract -Schema 'routing-context.result' -Object $resolved | Out-Null
        return $resolved
    }
    $unresolved = [PSCustomObject]@{
        schemaVersion     = 1
        registryName      = ''
        root              = ''
        routingConfidence = 0.0
        routingEvidence   = 'unresolved'
        minimumConfidence = $min
        eligible          = $false
    }
    Test-LoomContract -Schema 'routing-context.result' -Object $unresolved | Out-Null
    return $unresolved
}

function Invoke-LoomInspectAdapter {
    [CmdletBinding()]
    param($Request)
    return [PSCustomObject]@{
        schemaVersion = 1
        status        = 'not-implemented'
        goalMet       = $false
        message       = 'Inspect adapter stubs until Slice 4.'
    }
}

function Invoke-LoomImplementerAdapter {
    <#
    .SYNOPSIS
        Slice 3 implementer — Metra host delegate or test scriptblock. No direct scripts/private imports.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [scriptblock]$ImplementerScript
    )

    if ($ImplementerScript) {
        return & $ImplementerScript $Request $ProjectRoot $RunDir
    }

    $cmd = Get-Command Invoke-MetraLoomImplementer -ErrorAction SilentlyContinue
    if ($cmd) {
        return & $cmd -Request $Request -ProjectRoot $ProjectRoot -RunDir $RunDir
    }

    return [PSCustomObject]@{
        schemaVersion = 1
        status        = 'adapter-unavailable'
        message       = 'Implementer adapter unavailable (Invoke-MetraLoomImplementer not loaded).'
        exitCode      = 127
    }
}

function Invoke-LoomVerifyAdapter {
    [CmdletBinding()]
    param($Request)
    return [PSCustomObject]@{
        schemaVersion = 1
        status        = 'not-implemented'
        passed        = $false
        message       = 'Verify adapter stubs until Slice 4.'
    }
}
