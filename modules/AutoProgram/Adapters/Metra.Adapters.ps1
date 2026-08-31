# Metra host adapters for AutoProgram. Domain code calls these only — never scripts/private/*.ps1.

function Get-AutoProgramHostRoot {
    [CmdletBinding()]
    param()
    if ($script:AutoProgramHostRootOverride) {
        return [System.IO.Path]::GetFullPath([string]$script:AutoProgramHostRootOverride)
    }
    $cmd = Get-Command Get-MetraRoot -ErrorAction SilentlyContinue
    if ($cmd) {
        return & $cmd
    }
    # Standalone fallback: module lives at <metra>/modules/AutoProgram
    $modRoot = $PSScriptRoot
    while ($modRoot -and (Split-Path -Leaf $modRoot) -ne 'AutoProgram') {
        $modRoot = Split-Path -Parent $modRoot
    }
    if ($modRoot) {
        $candidate = Split-Path -Parent (Split-Path -Parent $modRoot)
        if (Test-Path -LiteralPath (Join-Path $candidate 'metra.ps1')) {
            return $candidate
        }
    }
    throw 'AutoProgram host root unavailable (Metra not loaded and metra.ps1 not found).'
}

function Get-AutoProgramInspectPlanRoots {
    [CmdletBinding()]
    param(
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-AutoProgramHostRoot
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

function Test-AutoProgramRoutingAdapterAvailable {
    [CmdletBinding()]
    param()
    return $null -ne (Get-Command Get-MetraRoutingAmbiguity -ErrorAction SilentlyContinue)
}

function Test-AutoProgramCaptureAdapterAvailable {
    [CmdletBinding()]
    param()
    return $null -ne (Get-Command Get-MetraCaptureLedger -ErrorAction SilentlyContinue)
}

function Get-AutoProgramRoutingAmbiguity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [switch]$SkipTelemetry
    )
    if (-not (Test-AutoProgramRoutingAdapterAvailable)) {
        return [PSCustomObject]@{
            Primary   = $null
            Ambiguous = $true
            Mode      = 'adapter-unavailable'
        }
    }
    return & (Get-Command Get-MetraRoutingAmbiguity) -Query $Query -SkipTelemetry:$SkipTelemetry
}

function Get-AutoProgramCaptureLedger {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [int]$Limit = 40,
        [string]$Status = 'candidate'
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-AutoProgramHostRoot
    }
    if (-not (Test-AutoProgramCaptureAdapterAvailable)) {
        return @()
    }
    return @(& (Get-Command Get-MetraCaptureLedger) -MetraRoot $MetraRoot -Limit $Limit -Status $Status)
}

function Get-AutoProgramRoutingContext {
    <#
    .SYNOPSIS
        Adapter: routing-context.result shape (Contracts/v1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request
    )
    $query = [string](Get-AutoProgramProp -Object $Request -Name 'query' -Default '')
    $planPath = [string](Get-AutoProgramProp -Object $Request -Name 'planPath' -Default '')
    $min = 0.85
    if (-not [string]::IsNullOrWhiteSpace($planPath) -and (Test-Path -LiteralPath $planPath)) {
        $hostRoot = Get-AutoProgramHostRoot
        if (Test-AutoProgramPathWithinRoot -Path $planPath -Root $hostRoot) {
            $fromPlan = [PSCustomObject]@{
                schemaVersion       = 1
                registryName        = 'Metra'
                root                = $hostRoot
                routingConfidence   = 0.99
                routingEvidence     = 'plan-path-under-metra-root'
                minimumConfidence   = $min
                eligible            = $true
            }
            Test-AutoProgramContract -Schema 'routing-context.result' -Object $fromPlan | Out-Null
            return $fromPlan
        }
    }
    $amb = Get-AutoProgramRoutingAmbiguity -Query $(if ($query) { $query } else { $planPath }) -SkipTelemetry
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
        Test-AutoProgramContract -Schema 'routing-context.result' -Object $invalid | Out-Null
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
        Test-AutoProgramContract -Schema 'routing-context.result' -Object $resolved | Out-Null
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
    Test-AutoProgramContract -Schema 'routing-context.result' -Object $unresolved | Out-Null
    return $unresolved
}

function Invoke-AutoProgramInspectAdapter {
    [CmdletBinding()]
    param($Request)
    return [PSCustomObject]@{
        schemaVersion = 1
        status        = 'not-implemented'
        goalMet       = $false
        message       = 'Inspect adapter stubs until Slice 4.'
    }
}

function Invoke-AutoProgramVerifyAdapter {
    [CmdletBinding()]
    param($Request)
    return [PSCustomObject]@{
        schemaVersion = 1
        status        = 'not-implemented'
        passed        = $false
        message       = 'Verify adapter stubs until Slice 4.'
    }
}
