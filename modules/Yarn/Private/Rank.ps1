# yarn-rank-v1 deterministic scorecard.

function Measure-YarnRank {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [double]$ImpactOverride = -1
    )

    $reasons = New-Object System.Collections.Generic.List[string]

    $opPri = [double](Get-YarnProp -Object $Item -Name 'operatorPriority' -Default 0)
    if ($opPri -lt 0) { $opPri = 0 }
    if ($opPri -gt 0.40) { $opPri = 0.40 }
    if ($opPri -gt 0) { [void]$reasons.Add('operatorPriority') }

    $projectKey = [string](Get-YarnProp -Object $Item -Name 'projectKey' -Default '')
    $crit = 0.0
    if (-not [string]::IsNullOrWhiteSpace($projectKey)) {
        $crit = if ($projectKey -eq 'Metra') { 0.25 } else { 0.10 }
        [void]$reasons.Add('projectCriticality')
    }

    $urgency = [double](Get-YarnProp -Object $Item -Name 'urgency' -Default 0)
    if ($urgency -lt 0) { $urgency = 0 }
    if ($urgency -gt 0.20) { $urgency = 0.20 }
    if ($urgency -gt 0) { [void]$reasons.Add('urgency') }

    $strategic = [double](Get-YarnProp -Object $Item -Name 'strategicAlignment' -Default 0)
    if ($strategic -lt 0) { $strategic = 0 }
    if ($strategic -gt 0.15) { $strategic = 0.15 }
    if ($strategic -gt 0) {
        $atlasKind = [string](Get-YarnProp -Object $Item -Name 'atlasKind' -Default '')
        if ($atlasKind) {
            [void]$reasons.Add("strategicAlignment:atlasKind=$atlasKind")
        }
        else {
            [void]$reasons.Add('strategicAlignment')
        }
    }

    $calculatedImpact = [math]::Min(1.0, [math]::Round($opPri + $crit + $urgency + $strategic, 2))
    $effectiveImpact = $calculatedImpact
    $overrideReason = $null
    if ($ImpactOverride -ge 0) {
        $effectiveImpact = [math]::Min(1.0, [math]::Round($ImpactOverride, 2))
        $overrideReason = [string](Get-YarnProp -Object $Item -Name 'overrideReason' -Default 'operator-override')
        [void]$reasons.Add('impactOverride')
    }

    $ready = 0.0
    $title = [string](Get-YarnProp -Object $Item -Name 'title' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($title)) {
        $ready += 0.15
        [void]$reasons.Add('objectivePresent')
    }
    if (-not [string]::IsNullOrWhiteSpace($projectKey)) {
        $ready += 0.15
        [void]$reasons.Add('projectResolved')
    }
    $planPath = [string](Get-YarnProp -Object $Item -Name 'formalPlanPath' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($planPath) -and (Test-Path -LiteralPath $planPath)) {
        $ready += 0.20
        [void]$reasons.Add('formalDraftPresent')
    }
    if ([bool](Get-YarnProp -Object $Item -Name 'boundedTodosPresent' -Default $false)) {
        $ready += 0.15
        [void]$reasons.Add('boundedTodosPresent')
    }
    if ([bool](Get-YarnProp -Object $Item -Name 'verificationPathPresent' -Default $false)) {
        $ready += 0.15
        [void]$reasons.Add('verificationPathPresent')
    }
    if ([bool](Get-YarnProp -Object $Item -Name 'riskKnownAndAcceptable' -Default $false)) {
        $ready += 0.10
        [void]$reasons.Add('riskKnownAndAcceptable')
    }
    if ([bool](Get-YarnProp -Object $Item -Name 'dependenciesResolved' -Default $true)) {
        $ready += 0.10
        [void]$reasons.Add('dependenciesResolved')
    }
    $completionReady = [math]::Round($ready, 2)
    $total = [math]::Round(0.5 * $effectiveImpact + 0.5 * $completionReady, 2)
    $readyEnough = $completionReady -ge 0.70

    return [PSCustomObject]@{
        calculatedImpact   = $calculatedImpact
        impactOverride     = if ($ImpactOverride -ge 0) { [math]::Round($ImpactOverride, 2) } else { $null }
        effectiveImpact    = $effectiveImpact
        overrideReason     = $overrideReason
        completionReady    = $completionReady
        total              = $total
        readyEnough        = $readyEnough
        rankReasons        = @($reasons)
        rubricVersion      = Get-YarnRubricVersion
    }
}

function Sort-YarnBacklogItems {
    param([object[]]$Items)
    return @(
        $Items |
            Sort-Object `
                @{ Expression = { [double](Get-YarnProp -Object $_ -Name 'total' -Default 0) }; Descending = $true }, `
                @{ Expression = { [double](Get-YarnProp -Object $_ -Name 'effectiveImpact' -Default 0) }; Descending = $true }, `
                @{ Expression = { [string](Get-YarnProp -Object $_ -Name 'firstSeenAt' -Default '') }; Descending = $false }, `
                @{ Expression = { [string](Get-YarnProp -Object $_ -Name 'id' -Default '') }; Descending = $false }
    )
}
