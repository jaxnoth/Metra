# Yarn CLI harness — status|scan|backlog|pending|reconcile|pack|daily|synthesize|plan|plan-board

function Get-MetraYarnStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    Initialize-MetraYarnLayout -Root $Root
    $items = @(Get-MetraYarnBacklog -Root $Root)
    $links = @(Get-YarnPlanLinks -Root $Root)
    $lane = Get-YarnMemoryLaneState -Root $Root
    $byStatus = @{}
    foreach ($i in $items) {
        $s = [string](Get-YarnProp -Object $i -Name 'status' -Default 'idea')
        if (-not $byStatus.ContainsKey($s)) { $byStatus[$s] = 0 }
        $byStatus[$s]++
    }
    $atlasCount = @($items | Where-Object {
            [string](Get-YarnProp -Object $_ -Name 'sourceKind' -Default '') -eq 'atlas'
        }).Count
    return [PSCustomObject]@{
        root                   = $Root
        schemaVersion          = Get-YarnSchemaVersion
        handoffContractVersion = Get-YarnHandoffContractVersion
        packContractVersion    = Get-YarnPackContractVersion
        rubricVersion          = Get-YarnRubricVersion
        totalItems             = $items.Count
        atlasItemCount         = $atlasCount
        planLinkCount          = $links.Count
        byStatus               = $byStatus
        memoryLane             = [string]$lane.memoryLane
        memoryLaneUpdatedAt    = $lane.updatedAt
        memoryLaneLastError    = $lane.lastError
        approvalAvailable      = $true
        phase                  = 'B'
    }
}

function Invoke-YarnCommand {
    <#
    .SYNOPSIS
        CLI: yarn status|scan|backlog|pending|reconcile|pack|daily|synthesize|plan|plan-board
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-MetraYarnRoot
    }
    else {
        $Root = Get-MetraYarnRoot -Override $Root
    }

    Initialize-MetraYarnLayout -Root $Root

    switch ($Subcommand.ToLowerInvariant()) {
        'status' {
            return Get-MetraYarnStatus -Root $Root
        }
        'scan' {
            return Invoke-MetraYarnScan -Root $Root -MetraRoot $MetraRoot
        }
        'backlog' {
            $top = 40
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Top' -and ($i + 1) -lt $ArgsRest.Count) {
                    $top = [int]$ArgsRest[$i + 1]
                    $i++
                }
            }
            return @(Get-MetraYarnBacklog -Root $Root | Select-Object -First $top)
        }
        'pending' {
            return @(Get-MetraYarnPending -Root $Root)
        }
        'daily' {
            $doReconcile = $ArgsRest -contains '-Reconcile'
            $dry = $ArgsRest -contains '-DryRun'
            return Get-MetraYarnDaily -Root $Root -MetraRoot $MetraRoot -Reconcile:$doReconcile -DryRun:$dry
        }
        'reconcile' {
            $dry = $ArgsRest -contains '-DryRun'
            return Invoke-MetraYarnReconcile -Root $Root -MetraRoot $MetraRoot -DryRun:$dry
        }
        'pack' {
            $backlogId = $null
            $path = $null
            $dry = $false
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-BacklogId' -and ($i + 1) -lt $ArgsRest.Count) { $backlogId = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-Path' -and ($i + 1) -lt $ArgsRest.Count) { $path = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-DryRun') { $dry = $true }
            }
            if ($backlogId) {
                return Invoke-MetraYarnPack -Root $Root -MetraRoot $MetraRoot -BacklogId $backlogId -DryRun:$dry
            }
            if ($path) {
                return Invoke-MetraYarnPack -Root $Root -MetraRoot $MetraRoot -Path $path -DryRun:$dry
            }
            throw 'yarn pack requires -BacklogId <id> or -Path <plan.md> [-DryRun]'
        }
        'synthesize' {
            $backlogId = $null
            $fromCapture = $null
            $fromFuture = $null
            $fromMemory = $null
            $dry = $false
            $confirm = $false
            $force = $false
            $useAgent = $false
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-BacklogId' -and ($i + 1) -lt $ArgsRest.Count) { $backlogId = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-FromCapture' -and ($i + 1) -lt $ArgsRest.Count) { $fromCapture = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-FromFutureDev' -and ($i + 1) -lt $ArgsRest.Count) { $fromFuture = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-FromMemory' -and ($i + 1) -lt $ArgsRest.Count) { $fromMemory = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-DryRun') { $dry = $true }
                elseif ($ArgsRest[$i] -eq '-Confirm') { $confirm = $true }
                elseif ($ArgsRest[$i] -eq '-Force') { $force = $true }
                elseif ($ArgsRest[$i] -eq '-UseAgent') { $useAgent = $true }
            }
            $params = @{
                Root      = $Root
                MetraRoot = $MetraRoot
                DryRun    = $dry
                Confirm   = $confirm
                Force     = $force
                UseAgent  = $useAgent
            }
            if ($backlogId) { $params['BacklogId'] = $backlogId }
            if ($fromCapture) { $params['FromCapture'] = $fromCapture }
            if ($fromFuture) { $params['FromFutureDev'] = $fromFuture }
            if ($fromMemory) { $params['FromMemory'] = $fromMemory }
            return Invoke-MetraYarnSynthesize @params
        }
        'plan' {
            $inner = if ($ArgsRest.Count -gt 0) { $ArgsRest[0].ToLowerInvariant() } else { '' }
            if ($inner -eq 'approve') {
                $rest = @()
                if ($ArgsRest.Count -gt 1) { $rest = @($ArgsRest[1..($ArgsRest.Count - 1)]) }
                $backlogId = $null
                $path = $null
                $dry = $false
                $confirm = $false
                for ($i = 0; $i -lt $rest.Count; $i++) {
                    if ($rest[$i] -eq '-BacklogId' -and ($i + 1) -lt $rest.Count) { $backlogId = [string]$rest[$i + 1]; $i++ }
                    elseif ($rest[$i] -eq '-Path' -and ($i + 1) -lt $rest.Count) { $path = [string]$rest[$i + 1]; $i++ }
                    elseif ($rest[$i] -eq '-DryRun') { $dry = $true }
                    elseif ($rest[$i] -eq '-Confirm') { $confirm = $true }
                }
                $params = @{
                    Root      = $Root
                    MetraRoot = $MetraRoot
                    DryRun    = $dry
                    Confirm   = $confirm
                }
                if ($backlogId) { $params['BacklogId'] = $backlogId }
                if ($path) { $params['Path'] = $path }
                return Invoke-MetraYarnPlanApprove @params
            }
            throw "yarn plan: unknown subcommand '$inner' (use approve)"
        }
        'plan-board' {
            return Invoke-YarnPlanBoardCommand -ArgsRest $ArgsRest -Root $Root -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown yarn subcommand: $Subcommand. Use status|scan|backlog|pending|reconcile|pack|daily|synthesize|plan|plan-board"
        }
    }
}

function Invoke-YarnPlanBoardCommand {
    <#
    .SYNOPSIS
        CLI: plan-board sync|status|inventory|inventory apply -Confirm
    #>
    [CmdletBinding()]
    param(
        [string[]]$ArgsRest = @(),
        [string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-MetraYarnRoot
    }
    else {
        $Root = Get-MetraYarnRoot -Override $Root
    }
    Initialize-MetraYarnLayout -Root $Root

    if (-not $ArgsRest -or $ArgsRest.Count -eq 0) {
        throw "plan-board requires sync|status|inventory. Example: .\metra.ps1 plan-board status"
    }

    $sub = $ArgsRest[0].ToLowerInvariant()
    $rest = @()
    if ($ArgsRest.Count -gt 1) { $rest = @($ArgsRest[1..($ArgsRest.Count - 1)]) }

    switch ($sub) {
        'sync' {
            if ($rest -contains '-Inventory') {
                throw 'plan-board sync -Inventory is unsupported; use: plan-board inventory'
            }
            $dry = $rest -contains '-DryRun'
            return Invoke-MetraYarnPlanBoardSync -Root $Root -MetraRoot $MetraRoot -DryRun:$dry
        }
        'status' {
            return Get-MetraYarnPlanBoardStatus -Root $Root -MetraRoot $MetraRoot
        }
        'inventory' {
            $apply = ($rest.Count -gt 0 -and $rest[0].ToLowerInvariant() -eq 'apply')
            if ($apply) {
                $confirm = $rest -contains '-Confirm'
                $affirmNoise = $rest -contains '-AffirmNoise'
                $affirm = $null
                $affirmCluster = $null
                $as = $null
                for ($i = 0; $i -lt $rest.Count; $i++) {
                    $tok = [string]$rest[$i]
                    if ($tok -eq '-Affirm' -and ($i + 1) -lt $rest.Count) {
                        $parts = [System.Collections.Generic.List[string]]::new()
                        $i++
                        while ($i -lt $rest.Count -and -not ([string]$rest[$i]).StartsWith('-')) {
                            $parts.Add([string]$rest[$i])
                            $i++
                        }
                        $i--
                        $affirm = ($parts -join ',')
                    }
                    elseif ($tok -eq '-AffirmCluster' -and ($i + 1) -lt $rest.Count) { $affirmCluster = [string]$rest[$i + 1]; $i++ }
                    elseif ($tok -eq '-As' -and ($i + 1) -lt $rest.Count) { $as = [string]$rest[$i + 1]; $i++ }
                }
                return Invoke-MetraYarnPlanBoardInventoryApply -Root $Root -MetraRoot $MetraRoot -Confirm:$confirm `
                    -AffirmNoise:$affirmNoise -Affirm $affirm -AffirmCluster $affirmCluster -As $as
            }
            return Invoke-MetraYarnPlanBoardInventory -Root $Root -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown plan-board subcommand: $sub. Use sync|status|inventory|inventory apply -Confirm."
        }
    }
}
