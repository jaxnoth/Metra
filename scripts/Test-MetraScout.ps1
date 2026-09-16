# Metra Scout fixture tooling - permanent path inspection helper.
# -Probe (default): read-only health of Ask/Loom/Yarn against the Scout plan leaf.
# -Reset -Confirm: retire this Scout leaf only (clear Approve marks, drop Yarn row, supersede Loom item).
# Scout success path never uses Loom status failed - retire is superseded so the next Approve can enqueue.

[CmdletBinding(DefaultParameterSetName = 'Probe')]
param(
    [Parameter(ParameterSetName = 'Probe')]
    [switch]$Probe,

    [Parameter(ParameterSetName = 'Reset', Mandatory)]
    [switch]$Reset,

    [Parameter(ParameterSetName = 'Reset')]
    [switch]$Confirm,

    [string]$PlanPath,

    [string]$MetraRoot
)

$ErrorActionPreference = 'Stop'

function Get-ScoutMetraRoot {
    param([string]$Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return [System.IO.Path]::GetFullPath($Override)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-ScoutDefaultPlanPath {
    $plans = Join-Path $env:USERPROFILE '.cursor\plans'
    $preferred = Join-Path $plans 'Scout.plan.md'
    if (Test-Path -LiteralPath $preferred) { return [System.IO.Path]::GetFullPath($preferred) }
    $alt = Join-Path $plans 'Scout.md'
    if (Test-Path -LiteralPath $alt) { return [System.IO.Path]::GetFullPath($alt) }
    return [System.IO.Path]::GetFullPath($preferred)
}

function Get-ScoutProp {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        foreach ($p in $Object.PSObject.Properties) {
            if ([string]::Equals($p.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($null -eq $p.Value) { return $Default }
                return $p.Value
            }
        }
        return $Default
    }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Import-ScoutModules {
    param([Parameter(Mandatory)][string]$Root)
    $yarn = Join-Path $Root 'modules\Yarn\Yarn.psd1'
    $loom = Join-Path $Root 'modules\Loom\Loom.psd1'
    if (-not (Test-Path -LiteralPath $yarn)) { throw "Yarn module missing: $yarn" }
    # Yarn + Loom only. Ask probe is soft when Get-MetraAskCapability is absent
    # (full Metra.psd1 import re-enters Yarn/Loom and can drop session exports).
    Import-Module $yarn -Force
    if (Test-Path -LiteralPath $loom) {
        Import-Module $loom -Force
    }
}

function Save-ScoutPlanLinks {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Links
    )
    $doc = [ordered]@{
        schemaVersion = Get-YarnSchemaVersion
        links         = @($Links)
    }
    [void](Assert-YarnPlanLinksDocument -Document $doc -Path (Join-Path $Root 'plan-links.json'))
    $path = Join-Path $Root 'plan-links.json'
    Write-YarnAtomicUtf8Text -Path $path -Text (($doc | ConvertTo-Json -Depth 12) + "`n")
}

function Get-ScoutPlanLeaf {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFileName($Path)
}

function Get-ScoutSourceKey {
    param([Parameter(Mandatory)][string]$Path)
    return ('cursor-approve:' + (Get-ScoutPlanLeaf -Path $Path))
}

function Resolve-ScoutPlanPath {
    param([string]$PlanPath)
    if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
        $full = [System.IO.Path]::GetFullPath($PlanPath)
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Scout plan not found: $full"
        }
        return $full
    }
    $full = Get-ScoutDefaultPlanPath
    if (-not (Test-Path -LiteralPath $full)) {
        throw "Scout plan not found (expected Scout.plan.md under .cursor\plans): $full"
    }
    return $full
}

function New-ScoutFinding {
    param(
        [Parameter(Mandatory)][ValidateSet('ok', 'warn', 'fail')][string]$Severity,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [object]$Detail = $null
    )
    return [PSCustomObject]@{
        severity = $Severity
        code     = $Code
        message  = $Message
        detail   = $Detail
    }
}

function Invoke-ScoutProbe {
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [Parameter(Mandatory)][string]$PlanPath
    )

    $findings = [System.Collections.ArrayList]::new()
    $yarnRoot = Get-MetraYarnRoot
    $leaf = Get-ScoutPlanLeaf -Path $PlanPath
    $sourceKey = Get-ScoutSourceKey -Path $PlanPath
    $planFull = [System.IO.Path]::GetFullPath($PlanPath)

    # Ask / inspect capability (optional - requires Metra host already loaded)
    $askCmd = Get-Command Get-MetraAskCapability -ErrorAction SilentlyContinue
    if (-not $askCmd) {
        [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'ask-cmd-missing' -Message 'Get-MetraAskCapability unavailable in this session (load Metra host for Ask probe).'))
    }
    else {
        try {
            $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
            $healthy = [bool](Get-ScoutProp -Object $cap -Name 'engineHealthy' -Default $false)
            $available = [bool](Get-ScoutProp -Object $cap -Name 'available' -Default $false)
            if (-not $available -or -not $healthy) {
                [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'ask-unhealthy' -Message ('Ask capability not healthy (available={0} engineHealthy={1} reason={2}).' -f $available, $healthy, (Get-ScoutProp -Object $cap -Name 'reason' -Default ''))))
            }
            else {
                [void]$findings.Add((New-ScoutFinding -Severity 'ok' -Code 'ask-healthy' -Message 'Ask capability healthy.'))
            }
        }
        catch {
            [void]$findings.Add((New-ScoutFinding -Severity 'fail' -Code 'ask-error' -Message $_.Exception.Message))
        }
    }

    # Loom pause
    $loomRootCmd = Get-Command Resolve-MetraLoomRoot -ErrorAction SilentlyContinue
    $pauseCmd = Get-Command Get-LoomLoopPauseState -ErrorAction SilentlyContinue
    $loomRootPath = $null
    if ($loomRootCmd) {
        try { $loomRootPath = [string]((Resolve-MetraLoomRoot).Path) } catch { $loomRootPath = $null }
    }
    if (-not $pauseCmd -or [string]::IsNullOrWhiteSpace($loomRootPath)) {
        [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'loom-pause-unavailable' -Message 'Loom pause state unavailable.'))
    }
    else {
        $pause = Get-LoomLoopPauseState -Root $loomRootPath
        $paused = [bool](Get-ScoutProp -Object $pause -Name 'loopPaused' -Default $false)
        $reason = [string](Get-ScoutProp -Object $pause -Name 'pauseReason' -Default '')
        if ($paused -and $reason -match '(?i)^inspect-') {
            [void]$findings.Add((New-ScoutFinding -Severity 'fail' -Code 'loom-inspect-pause' -Message ("Loom sticky inspect pause: $reason")))
        }
        elseif ($paused) {
            [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'loom-paused' -Message ("Loom loopPaused: $reason")))
        }
        else {
            [void]$findings.Add((New-ScoutFinding -Severity 'ok' -Code 'loom-not-paused' -Message 'Loom not paused.'))
        }
    }

    # Plan eligibility + Metra root resolve
    $enc = Get-YarnUtf8NoBomEncoding
    $planText = [System.IO.File]::ReadAllText($PlanPath, $enc)
    $elig = Test-YarnContentBoundLoomEligibility -PlanText $planText
    if ($elig.eligible) {
        [void]$findings.Add((New-ScoutFinding -Severity 'ok' -Code 'eligible' -Message 'Content-bound Loom gates current.' -Detail $elig.currentContentHash))
    }
    else {
        # Not Approved is normal for a retired/idle Scout - soft unless hashes are stale while marked true.
        $reason = [string]$elig.reason
        $sev = if ($reason -match '(?i)stale') { 'fail' } else { 'warn' }
        [void]$findings.Add((New-ScoutFinding -Severity $sev -Code 'not-eligible' -Message ("Not Loom-eligible: $reason") -Detail $elig.currentContentHash))
    }

    $resolveCmd = Get-Command Resolve-MetraLoomPlanProject -ErrorAction SilentlyContinue
    if ($resolveCmd) {
        $proj = Resolve-MetraLoomPlanProject -Path $PlanPath -MetraRoot $MetraRoot -Title 'Scout' -Overview 'Metra Scout'
        $root = [string](Get-ScoutProp -Object $proj -Name 'root' -Default '')
        $reg = [string](Get-ScoutProp -Object $proj -Name 'registryName' -Default '')
        if ([string]::IsNullOrWhiteSpace($root) -or $reg -ne 'Metra') {
            [void]$findings.Add((New-ScoutFinding -Severity 'fail' -Code 'project-root' -Message ('project.root would not resolve for Metra (registryName={0}).' -f $reg) -Detail $proj))
        }
        else {
            [void]$findings.Add((New-ScoutFinding -Severity 'ok' -Code 'project-root' -Message 'Metra project.root resolves.' -Detail $root))
        }
    }
    else {
        [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'project-root-unavailable' -Message 'Resolve-MetraLoomPlanProject unavailable.'))
    }

    # Yarn backlog / plan-link
    $backlog = @(Get-MetraYarnBacklog -Root $yarnRoot)
    $matchItems = @($backlog | Where-Object {
            $psk = [string](Get-ScoutProp -Object $_ -Name 'primarySourceKey' -Default '')
            $fp = [string](Get-ScoutProp -Object $_ -Name 'formalPlanPath' -Default '')
            ($psk -eq $sourceKey) -or (
                -not [string]::IsNullOrWhiteSpace($fp) -and
                ([System.IO.Path]::GetFullPath($fp) -eq $planFull)
            )
        })
    if ($matchItems.Count -gt 0) {
        [void]$findings.Add((New-ScoutFinding -Severity 'ok' -Code 'yarn-backlog' -Message ('Yarn backlog has {0} Scout row(s).' -f $matchItems.Count) -Detail (@($matchItems | ForEach-Object { $_.id }))))
    }
    else {
        [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'yarn-backlog-absent' -Message 'No Yarn backlog row for Scout leaf (expected after Approve+scan; expected absent after retire).'))
    }

    $links = @(Get-YarnPlanLinks -Root $yarnRoot)
    $matchLinks = @($links | Where-Object {
            $bid = [string](Get-ScoutProp -Object $_ -Name 'backlogId' -Default '')
            $matchItems.id -contains $bid
        })
    if ($matchItems.Count -gt 0 -and $matchLinks.Count -eq 0) {
        [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'yarn-plan-link-absent' -Message 'Scout backlog row present but no plan-link.'))
    }
    elseif ($matchLinks.Count -gt 0) {
        [void]$findings.Add((New-ScoutFinding -Severity 'ok' -Code 'yarn-plan-link' -Message ('Yarn plan-link present ({0}).' -f $matchLinks.Count)))
    }

    # Loom queue match
    if ($loomRootPath -and (Get-Command Get-MetraLoomQueueItems -ErrorAction SilentlyContinue)) {
        $items = @(Get-MetraLoomQueueItems -Root $loomRootPath)
        $matchQ = @($items | Where-Object {
                $yh = Get-ScoutProp -Object $_ -Name 'yarnHandoff' -Default $null
                $pi = [string](Get-ScoutProp -Object $yh -Name 'planIdentity' -Default '')
                $pi -and $pi.ToLowerInvariant().Contains($planFull.ToLowerInvariant())
            })
        if ($matchQ.Count -eq 0) {
            [void]$findings.Add((New-ScoutFinding -Severity 'warn' -Code 'loom-queue-absent' -Message 'No Loom queue item for Scout plan (ok before handoff / after retire).'))
        }
        else {
            foreach ($qi in $matchQ) {
                [void]$findings.Add((New-ScoutFinding -Severity 'ok' -Code 'loom-queue' -Message ('Loom {0} status={1}' -f $qi.id, $qi.status) -Detail ([PSCustomObject]@{ id = $qi.id; status = $qi.status; laneHeld = (Get-ScoutProp -Object $qi -Name 'laneHeld' -Default $null) })))
            }
        }
    }

    $hard = @(@($findings) | Where-Object { $_.severity -eq 'fail' }).Count
    $warn = @(@($findings) | Where-Object { $_.severity -eq 'warn' }).Count
    $exitCode = 0
    $outcome = 'ok'
    if ($hard -gt 0) {
        $exitCode = 1
        $outcome = 'fail'
    }
    elseif ($warn -gt 0) {
        $outcome = 'warn'
    }
    return [PSCustomObject]@{
        outcome   = $outcome
        exitCode  = $exitCode
        planPath  = $PlanPath
        leaf      = $leaf
        sourceKey = $sourceKey
        findings  = @($findings)
        hardFails = $hard
        warnings  = $warn
    }
}

function Invoke-ScoutReset {
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [Parameter(Mandatory)][string]$PlanPath,
        [switch]$Confirm
    )

    if (-not $Confirm) {
        throw 'Test-MetraScout -Reset requires -Confirm'
    }

    $yarnRoot = Get-MetraYarnRoot
    $leaf = Get-ScoutPlanLeaf -Path $PlanPath
    $sourceKey = Get-ScoutSourceKey -Path $PlanPath
    $planFull = [System.IO.Path]::GetFullPath($PlanPath)
    $actions = [System.Collections.ArrayList]::new()

    # 1) Clear Approve marks on this plan only
    $null = Set-YarnPlanFrontmatterFields -Path $PlanPath -Fields @{
        approveForLoom     = $false
        approveForLoomHash = $null
        externalReviewed   = $false
        externalReviewHash = $null
        loomHandoffId      = $null
        loomAcceptedAt     = $null
        status             = 'pending'
    }
    [void]$actions.Add([PSCustomObject]@{ step = 'plan-marks'; result = 'cleared'; path = $PlanPath })

    # 2) Remove matching Yarn backlog + plan-links
    $backlog = @(Get-MetraYarnBacklog -Root $yarnRoot)
    $keep = @()
    $removedIds = @()
    foreach ($item in $backlog) {
        $psk = [string](Get-ScoutProp -Object $item -Name 'primarySourceKey' -Default '')
        $fp = [string](Get-ScoutProp -Object $item -Name 'formalPlanPath' -Default '')
        $match = ($psk -eq $sourceKey) -or (
            -not [string]::IsNullOrWhiteSpace($fp) -and
            ([System.IO.Path]::GetFullPath($fp) -eq $planFull)
        )
        if ($match) {
            $removedIds += [string]$item.id
        }
        else {
            $keep += $item
        }
    }
    if ($removedIds.Count -gt 0) {
        Save-MetraYarnBacklogItems -Root $yarnRoot -Items $keep
        $links = @(Get-YarnPlanLinks -Root $yarnRoot)
        $keptLinks = @($links | Where-Object {
                $bid = [string](Get-ScoutProp -Object $_ -Name 'backlogId' -Default '')
                $removedIds -notcontains $bid
            })
        Save-ScoutPlanLinks -Root $yarnRoot -Links $keptLinks
        [void]$actions.Add([PSCustomObject]@{ step = 'yarn-backlog'; result = 'removed'; ids = $removedIds })
    }
    else {
        [void]$actions.Add([PSCustomObject]@{ step = 'yarn-backlog'; result = 'absent' })
    }

    # 3) Supersede matching Loom queue items (frees Metra lane; not a failure).
    # Terminal failed/rejected/accepted/superseded rows are left alone. Next Approve + ingest
    # creates a fresh AP-* because Yarn handoff lookup skips terminal queue rows.
    $supersededIds = @()
    $loomRootCmd = Get-Command Resolve-MetraLoomRoot -ErrorAction SilentlyContinue
    if ($loomRootCmd -and (Get-Command Get-MetraLoomQueueItems -ErrorAction SilentlyContinue)) {
        $loomRootPath = [string]((Resolve-MetraLoomRoot).Path)
        $items = @(Get-MetraLoomQueueItems -Root $loomRootPath)
        foreach ($qi in $items) {
            $status = [string](Get-ScoutProp -Object $qi -Name 'status' -Default '')
            if ($status -match '(?i)^(accepted|failed|rejected|superseded)$') { continue }
            $yh = Get-ScoutProp -Object $qi -Name 'yarnHandoff' -Default $null
            $pi = [string](Get-ScoutProp -Object $yh -Name 'planIdentity' -Default '')
            if (-not $pi -or -not $pi.ToLowerInvariant().Contains($planFull.ToLowerInvariant())) { continue }
            $qi | Add-Member -NotePropertyName status -NotePropertyValue 'superseded' -Force
            $qi | Add-Member -NotePropertyName laneHeld -NotePropertyValue $false -Force
            $qi | Add-Member -NotePropertyName lastError -NotePropertyValue 'scout-retire' -Force
            $qi | Add-Member -NotePropertyName updatedAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
            Save-MetraLoomQueueItem -Root $loomRootPath -Item $qi
            $supersededIds += [string]$qi.id
        }
    }
    if ($supersededIds.Count -gt 0) {
        [void]$actions.Add([PSCustomObject]@{ step = 'loom-queue'; result = 'superseded'; ids = $supersededIds; reason = 'scout-retire' })
    }
    else {
        [void]$actions.Add([PSCustomObject]@{ step = 'loom-queue'; result = 'absent-or-terminal' })
    }

    return [PSCustomObject]@{
        outcome   = 'retired'
        exitCode  = 0
        planPath  = $PlanPath
        leaf      = $leaf
        sourceKey = $sourceKey
        actions   = @($actions)
    }
}

# --- main ---
if ($PSCmdlet.ParameterSetName -eq 'Probe' -and -not $Probe) {
    $Probe = $true
}

$root = Get-ScoutMetraRoot -Override $MetraRoot
Import-ScoutModules -Root $root
$plan = Resolve-ScoutPlanPath -PlanPath $PlanPath

if ($Reset) {
    $result = Invoke-ScoutReset -MetraRoot $root -PlanPath $plan -Confirm:$Confirm
}
else {
    $result = Invoke-ScoutProbe -MetraRoot $root -PlanPath $plan
}

$result | ConvertTo-Json -Depth 8
exit [int]$result.exitCode
