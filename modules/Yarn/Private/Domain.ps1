# Yarn CLI harness — status|scan|backlog|pending|reconcile|pack|daily|synthesize

function Get-MetraYarnStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    Initialize-MetraYarnLayout -Root $Root
    $items = @(Get-MetraYarnBacklog -Root $Root)
    $links = @(Get-YarnPlanLinks -Root $Root)
    $byStatus = @{}
    foreach ($i in $items) {
        $s = [string](Get-YarnProp -Object $i -Name 'status' -Default 'idea')
        if (-not $byStatus.ContainsKey($s)) { $byStatus[$s] = 0 }
        $byStatus[$s]++
    }
    return [PSCustomObject]@{
        root                   = $Root
        schemaVersion          = Get-YarnSchemaVersion
        handoffContractVersion = Get-YarnHandoffContractVersion
        packContractVersion    = Get-YarnPackContractVersion
        rubricVersion          = Get-YarnRubricVersion
        totalItems             = $items.Count
        planLinkCount          = $links.Count
        byStatus               = $byStatus
        approvalAvailable      = $true
        phase                  = 'A3'
    }
}

function Invoke-YarnCommand {
    <#
    .SYNOPSIS
        CLI: yarn status|scan|backlog|pending|reconcile|pack|daily|synthesize|plan
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
            $dry = $false
            $confirm = $false
            $force = $false
            $useAgent = $false
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-BacklogId' -and ($i + 1) -lt $ArgsRest.Count) { $backlogId = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-FromCapture' -and ($i + 1) -lt $ArgsRest.Count) { $fromCapture = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-FromFutureDev' -and ($i + 1) -lt $ArgsRest.Count) { $fromFuture = [string]$ArgsRest[$i + 1]; $i++ }
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
        default {
            throw "Unknown yarn subcommand: $Subcommand. Use status|scan|backlog|pending|reconcile|pack|daily|synthesize|plan"
        }
    }
}
