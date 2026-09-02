# yarn daily — read-only report by default (A1). -Reconcile opt-in mutates via A2 path.

function Get-MetraYarnDaily {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [switch]$Reconcile,
        [switch]$DryRun
    )

    if ($Reconcile) {
        $rec = Invoke-MetraYarnReconcile -Root $Root -MetraRoot $MetraRoot -DryRun:$DryRun
        return [PSCustomObject]@{
            outcome   = 'daily-with-reconcile'
            root      = $Root
            reconcile = $rec
            pending   = @(Get-MetraYarnPending -Root $Root)
            backlog   = @(Get-MetraYarnBacklog -Root $Root | Select-Object -First 20 id, title, status, total, readyEnough, projectKey)
        }
    }

    $items = @(Get-MetraYarnBacklog -Root $Root)
    $byStatus = @{}
    foreach ($i in $items) {
        $s = [string](Get-YarnProp -Object $i -Name 'status' -Default 'idea')
        if (-not $byStatus.ContainsKey($s)) { $byStatus[$s] = 0 }
        $byStatus[$s]++
    }
    $pending = @(Get-MetraYarnPending -Root $Root)
    $needsSynth = @($items | Where-Object {
            $path = [string](Get-YarnProp -Object $_ -Name 'formalPlanPath' -Default '')
            $st = [string](Get-YarnProp -Object $_ -Name 'status' -Default 'idea')
            $st -notin @('parked', 'rejected', 'approved') -and (
                [string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)
            )
        })

    return [PSCustomObject]@{
        outcome            = 'daily-readonly'
        root               = $Root
        schemaVersion      = Get-YarnSchemaVersion
        rubricVersion      = Get-YarnRubricVersion
        totalItems         = $items.Count
        byStatus           = $byStatus
        topRanked          = @($items | Select-Object -First 10 id, title, status, total, completionReady, readyEnough, projectKey, primarySourceKey)
        pendingBingCount   = $pending.Count
        needsSynthesizeCount = $needsSynth.Count
        approvalAvailable  = $true
        note               = 'A3: yarn plan approve -BacklogId <id> -Confirm after pending-bing + fresh pack. Reconcile retries failed handoff.'
    }
}
